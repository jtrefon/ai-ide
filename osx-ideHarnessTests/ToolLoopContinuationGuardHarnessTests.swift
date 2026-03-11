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

    func testRecoverySummaryDoesNotTriggerRedundantPlanContinuation() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Finish implementation"))

        let firstToolCall = AIToolCall(id: "continuation-guard-1", name: "fake_tool", arguments: [:])
        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: Need to execute the next step.\nPlanning: Run a single task.\nContinuity: Work remains.\nDelivery: NEEDS_WORK</ide_reasoning>Starting execution now.",
                toolCalls: [firstToolCall]
            ),
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: First step completed.\nPlanning: Continue remaining work.\nContinuity: Pending tasks remain.\nDelivery: NEEDS_WORK</ide_reasoning>Done -> Next -> Path: Continue with remaining implementation.",
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
            explicitContext: nil,
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
        XCTAssertEqual(executedToolMessages.count, 1)

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content
        print("[HARNESS][INFO] finalAssistantOutput=\(finalAssistantOutput ?? "<nil>")")
        XCTAssertEqual(
            finalAssistantOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Done -> Next -> Path: Continue with remaining implementation."
        )

        let followupRequests = scriptedService.capturedHistoryRequests()
        let requestStages = followupRequests.map { $0.stage?.rawValue ?? "nil" }.joined(separator: ",")
        print("[HARNESS][INFO] followupRequestStages=\(requestStages)")
        XCTAssertEqual(followupRequests.count, 2)
        XCTAssertEqual(requestStages, "initial_response,tool_loop")
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

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            - [ ] Resolve dependency conflicts
            - [ ] Verify installation
            """
        )

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(
                content: "Start by checking the current dependency state.",
                toolCalls: [initialToolCall]
            ),
            explicitContext: nil,
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

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        XCTAssertEqual(executedToolMessages.count, 2)

        let followupRequests = scriptedService.capturedHistoryRequests()
        let requestStages = followupRequests.map { $0.stage?.rawValue ?? "nil" }
        XCTAssertGreaterThanOrEqual(requestStages.count, 2)
        XCTAssertTrue(requestStages.allSatisfy { $0 == "tool_loop" })
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        return ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
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
