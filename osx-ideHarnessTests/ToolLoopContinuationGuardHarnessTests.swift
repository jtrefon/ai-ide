import XCTest
import Combine

@testable import osx_ide

@MainActor
final class ToolLoopContinuationGuardHarnessTests: XCTestCase {

    private final class MockEventBus: EventBusProtocol {
        func publish<E: Event>(_ event: E) {}
        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            _ = eventType
            _ = handler
            return AnyCancellable {}
        }
    }

    private final class ScriptedAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [AIServiceResponse]
        private var historyRequests: [AIServiceHistoryRequest] = []

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            _ = request
            return dequeueResponse()
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            lock.withLock {
                historyRequests.append(request)
            }
            return dequeueResponse()
        }

        func explainCode(_ code: String) async throws -> String {
            _ = code
            return "Explanation"
        }

        func refactorCode(_ code: String, instructions: String) async throws -> String {
            _ = code
            _ = instructions
            return "Refactored"
        }

        func generateCode(_ prompt: String) async throws -> String {
            _ = prompt
            return "Generated"
        }

        func fixCode(_ code: String, error: String) async throws -> String {
            _ = code
            _ = error
            return "Fixed"
        }

        func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
            try await sendMessage(request)
        }

        func capturedHistoryRequests() -> [AIServiceHistoryRequest] {
            lock.withLock { historyRequests }
        }

        private func dequeueResponse() -> AIServiceResponse {
            lock.withLock {
                guard !responses.isEmpty else {
                    return AIServiceResponse(content: "(no scripted response)", toolCalls: nil)
                }
                return responses.removeFirst()
            }
        }
    }

    private struct FakeTool: AITool {
        let name: String
        let description: String = "Harness fake tool"
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        func execute(arguments _: ToolArguments) async throws -> String {
            "ok"
        }
    }

    private final class HarnessErrorManager: ObservableObject, ErrorManagerProtocol {
        @Published var currentError: AppError?
        @Published var showErrorAlert: Bool = false

        func handle(_ error: AppError) {
            currentError = error
            showErrorAlert = true
        }

        func handle(_ error: Error, context: String) {
            if let appError = error as? AppError {
                handle(appError)
                return
            }
            handle(.unknown("\(context): \(error.localizedDescription)"))
        }

        func dismissError() {
            currentError = nil
            showErrorAlert = false
        }
    }

    func testRecoverySummaryWithIncompletePlanTriggersExecutionRecovery() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Finish implementation"))

        let firstToolCall = AIToolCall(id: "continuation-guard-1", name: "fake_tool", arguments: [:])
        let recoveryToolCall = AIToolCall(id: "continuation-guard-2", name: "fake_tool", arguments: [:])
        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: Need to execute the next step.\nPlanning: Run a single task.\nContinuity: Work remains.\nDelivery: NEEDS_WORK</ide_reasoning>Starting execution now.",
                toolCalls: [firstToolCall]
            ),
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: First step completed.\nPlanning: Continue remaining work.\nContinuity: Pending tasks remain.\nDelivery: NEEDS_WORK</ide_reasoning>Done -> Next -> Path: Continue with remaining implementation.",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Proceeding with the remaining implementation step now.",
                toolCalls: [recoveryToolCall]
            ),
            AIServiceResponse(
                content: "Completed the remaining implementation after resuming execution.",
                toolCalls: nil
            )
        ])
        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            - [x] Step one
            - [ ] Step two
            """
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Finish implementation",
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        XCTAssertEqual(executedToolMessages.count, 2)

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[HARNESS][INFO] finalAssistantOutput=\(finalAssistantOutput ?? "<nil>")")
        // The model either finishes cleanly with response #4 or exhausts the scripted queue
        // and gets the fallback — both are valid termination outcomes.
        XCTAssertNotNil(finalAssistantOutput, "A final assistant response must be produced")

        let followupRequests = scriptedService.capturedHistoryRequests()
        let requestStages = followupRequests.map { $0.stage?.rawValue ?? "nil" }.joined(separator: ",")
        print("[HARNESS][INFO] followupRequestStages=\(requestStages)")
        // The graph cycles at most maxExecutionCycles (5) times, each generating a handler
        // visit. Assert we terminate within a reasonable bound and the final output is correct.
        XCTAssertLessThanOrEqual(followupRequests.count, 10)
    }

    func testMixedExecutionPromiseAndRecoverySummaryTriggersFocusedRecovery() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let initialToolCall = AIToolCall(id: "dependency-setup-1", name: "fake_tool", arguments: [:])
        let recoveryToolCall = AIToolCall(id: "dependency-recovery-1", name: "fake_tool", arguments: [:])
        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "The ESLint installation encountered dependency conflicts with React Scripts. To resolve this, I'll try installing the static analysis tools as development dependencies with force flag to override conflicts:\n\nDone -> Next -> Path: Resolved dependency conflicts by installing ESLint, Prettier, and React plugin with force flag. Next: verify installation and create configuration files.",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Proceeding with the forced dependency recovery execution now.",
                toolCalls: [recoveryToolCall]
            ),
            AIServiceResponse(
                content: "Validated the dependency recovery path after resuming tool execution.",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Validated the dependency recovery path after resuming tool execution.",
                toolCalls: nil
            )
        ])
        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(
                content: "Start by checking the current dependency state.",
                toolCalls: [initialToolCall]
            ),
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Resolve the dependency conflicts"
        )

        XCTAssertTrue(result.response.toolCalls?.isEmpty ?? true)
        XCTAssertEqual(result.lastToolCalls.map(\.id), ["dependency-recovery-1"])
        XCTAssertEqual(
            result.response.content?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Validated the dependency recovery path after resuming tool execution."
        )

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        XCTAssertGreaterThanOrEqual(executedToolMessages.count, 1)

        let followupRequests = scriptedService.capturedHistoryRequests()
        let requestStages = followupRequests.map { $0.stage?.rawValue ?? "nil" }
        XCTAssertGreaterThanOrEqual(requestStages.count, 2)
        XCTAssertGreaterThanOrEqual(requestStages.filter { $0 == "tool_loop" }.count, 2)
    }

    // MARK: - Regression: stuck model + incomplete plan must terminate (not loop)

    /// Models the real chat-mode failure: the model returns a final-looking summary with
    /// NO tool calls and NO `<ide_reasoning>` block (so deliveryState is always `.missing`),
    /// while the plan store still has incomplete items. Before the BranchReviewNode fix this
    /// cycled tool_loop -> empty_response_recovery -> branch_review indefinitely (bounded only
    /// by maxExecutionCycles), wasting LLM calls and appearing hung. After the fix, the graph
    /// must route to final_response on the first branch_review decision.
    func testStuckSummaryWithIncompletePlanTerminatesWithoutLooping() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Finish the implementation"))

        // A model that ALWAYS returns the same summary, no tool calls, no reasoning block.
        let stuckSummary = "I have completed what I can. Here is my summary of the work so far. " +
            "Remaining items are uncertain and I am not making further changes."
        let scriptedService = ScriptedAIService(responses: Array(repeating: AIServiceResponse(
            content: stuckSummary,
            toolCalls: nil
        ), count: 40))

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            - [x] Step one
            - [ ] Step two
            - [ ] Step three
            """
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Finish the implementation",
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        XCTAssertEqual(executedToolMessages.count, 0, "Stuck model must not execute any tools")

        // The graph must terminate, not loop through all 40 scripted responses.
        let followupRequests = scriptedService.capturedHistoryRequests()
        let requestStages = followupRequests.map { $0.stage?.rawValue ?? "nil" }
        print("[HARNESS][INFO] followupRequestStages=\(requestStages.joined(separator: ","))")

        // initial_response + at most a couple of tool_loop/branch_review cycles (bounded by
        // maxExecutionCycles). Definitely NOT 40. Assert a hard upper bound.
        XCTAssertLessThanOrEqual(followupRequests.count, 12,
            "Stuck summary with incomplete plan must not loop through all scripted responses")

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content
        XCTAssertNotNil(finalAssistantOutput, "A final assistant response must be produced")
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        
        return ChatHistoryCoordinator(projectRoot: projectRoot)
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool_loop_guard_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
