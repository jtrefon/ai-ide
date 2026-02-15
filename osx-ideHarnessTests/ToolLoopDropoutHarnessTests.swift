import XCTest
@testable import osx_ide

@MainActor
final class ToolLoopDropoutHarnessTests: XCTestCase {
    private final class ScriptedAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [AIServiceResponse]

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            _ = request
            return dequeueResponse()
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            _ = request
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

        private func dequeueResponse() -> AIServiceResponse {
            lock.lock()
            defer { lock.unlock() }
            guard !responses.isEmpty else {
                return AIServiceResponse(content: "(no scripted response)", toolCalls: nil)
            }
            return responses.removeFirst()
        }
    }

    private actor ToolExecutionCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    private struct CountingTool: AITool {
        let name: String
        let description: String = "Counting harness tool"
        let counter: ToolExecutionCounter
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        func execute(arguments _: ToolArguments) async throws -> String {
            await counter.increment()
            return "counted"
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

    func testHarnessReproducesAndPreventsBallDropForIncompletePlan() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            ## Strategy
            - [ ] Step one
            - [ ] Step two
            """
        )

        historyCoordinator.append(ChatMessage(
            role: .assistant,
            content: """
            # Implementation Plan

            ## Strategy
            - [ ] Step one
            - [ ] Step two
            """
        ))

        let firstToolCall = AIToolCall(id: "call-1", name: "fake_tool", arguments: [:])
        let secondToolCall = AIToolCall(id: "call-2", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            // After first tool execution, model drops out with no tool call even though plan is unfinished.
            AIServiceResponse(content: "I think this should be enough for now.", toolCalls: nil),
            // Continuation guardrail should force this follow-up tool call.
            AIServiceResponse(content: "Continuing unfinished checklist item.", toolCalls: [secondToolCall]),
            // After second tool execution, model can finish.
            AIServiceResponse(content: "<ide_reasoning>Analyze: done\nPlan: done\nAction: none\nDelivery: DONE</ide_reasoning>All checklist items are complete.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil)
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

        let availableTools: [AITool] = [FakeTool(name: "fake_tool")]

        let firstPass = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Starting execution.", toolCalls: [firstToolCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Complete implementation"
        )

        XCTAssertEqual(firstPass.lastToolCalls.map(\.id), ["call-1"])
        XCTAssertEqual(firstPass.response.toolCalls?.map(\.id), ["call-2"], "Guardrail should force continuation tool call instead of stopping early")

        let secondPass = try await handler.handleToolLoopIfNeeded(
            response: firstPass.response,
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Complete implementation"
        )

        XCTAssertTrue(secondPass.response.toolCalls?.isEmpty ?? true, "Second pass should finish without further tool calls")

        let finalPlan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let finalProgress = PlanChecklistTracker.progress(in: finalPlan)
        XCTAssertEqual(finalProgress.completed, finalProgress.total, "Plan should be fully completed after continuation")

        let planMessages = historyCoordinator.messages.filter {
            $0.role == .assistant && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# Implementation Plan")
        }
        XCTAssertEqual(planMessages.count, 1, "Plan should be updated in place, not duplicated")
    }

    func testHarnessDeduplicatesDuplicateToolCallsInSingleIteration() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "<ide_reasoning>Analyze: done\nPlan: done\nAction: none\nDelivery: DONE</ide_reasoning>Finished.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil)
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

        let counter = ToolExecutionCounter()
        let duplicateA = AIToolCall(id: "dup-1", name: "counting_tool", arguments: ["path": "src"]) 
        let duplicateB = AIToolCall(id: "dup-2", name: "counting_tool", arguments: ["path": "src"]) 
        let duplicateC = AIToolCall(id: "dup-3", name: "counting_tool", arguments: ["path": "src"]) 

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Exploring project.", toolCalls: [duplicateA, duplicateB, duplicateC]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: UUID().uuidString,
            userInput: "Convert static app to SSR"
        )

        XCTAssertEqual(result.lastToolCalls.count, 1, "Duplicate tool calls in one assistant message should be collapsed")
        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 1, "Only one deduplicated tool call should execute")
    }

    func testHarnessShortCircuitsRepeatedToolBatchesToAvoidSlowDropoutLoop() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Still scanning.", toolCalls: [AIToolCall(id: "loop-2", name: "counting_tool", arguments: ["query": "src"]) ]),
            AIServiceResponse(content: "Still scanning again.", toolCalls: [AIToolCall(id: "loop-3", name: "counting_tool", arguments: ["query": "src"]) ]),
            AIServiceResponse(content: "Final summary after repeated loop detection.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil)
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

        let counter = ToolExecutionCounter()
        let firstLoopCall = AIToolCall(id: "loop-1", name: "counting_tool", arguments: ["query": "src"]) 

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start scan.", toolCalls: [firstLoopCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Convert static app to SSR"
        )

        XCTAssertTrue(result.response.toolCalls?.isEmpty ?? true, "Handler should stop repeated batches and switch to final response")
        XCTAssertEqual(result.response.content, "Final summary after repeated loop detection.")
        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 2, "Repeated third identical batch should be prevented from executing")
    }

    func testHarnessStopsRepeatedPseudoToolCallContentWithoutStructuredToolCalls() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            - [ ] Migrate app to SSR
            """
        )

        historyCoordinator.append(ChatMessage(
            role: .assistant,
            content: """
            # Implementation Plan

            - [ ] Migrate app to SSR
            """
        ))

        let loopCall = AIToolCall(id: "loop-pseudo-1", name: "counting_tool", arguments: ["query": "src"])
        let pseudoToolCallContent = """
        <ide_reasoning>
        Analyze: Migrating to SSR.
        Plan: Create Next.js app.
        Action: Begin migration.
        </ide_reasoning>
        Tool calls:create_next_app("my-ssr-app", "--use-npm")
        """

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: pseudoToolCallContent, toolCalls: nil),
            AIServiceResponse(content: pseudoToolCallContent, toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil)
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

        let counter = ToolExecutionCounter()
        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start execution.", toolCalls: [loopCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Migrate app to SSR"
        )

        XCTAssertTrue(result.response.toolCalls?.isEmpty ?? true)
        XCTAssertTrue(
            result.response.content?.contains("Tool calls:create_next_app") ?? false,
            "Handler should return textual pseudo-tool-call content without entering a repeated execution loop"
        )
        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 1, "Pseudo textual tool calls must not trigger repeated execution loops")
    }

    func testHarnessShortCircuitsRepeatedReadOnlyCheckpointLoop() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Still checking checkpoints.", toolCalls: [
                AIToolCall(id: "checkpoint-loop-2", name: "checkpoint_list", arguments: [:])
            ]),
            AIServiceResponse(content: "Checking checkpoints again.", toolCalls: [
                AIToolCall(id: "checkpoint-loop-3", name: "checkpoint_list", arguments: [:])
            ]),
            AIServiceResponse(content: "Stopped repeated read-only checkpoint loop and returning summary.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil)
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

        let counter = ToolExecutionCounter()
        let firstCall = AIToolCall(id: "checkpoint-loop-1", name: "checkpoint_list", arguments: [:])

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start checkpoint scan.", toolCalls: [firstCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "checkpoint_list", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: UUID().uuidString,
            userInput: "Inspect and use checkpoints to continue execution"
        )

        XCTAssertTrue(result.response.toolCalls?.isEmpty ?? true, "Read-only checkpoint loop should be stopped")
        XCTAssertEqual(
            result.response.content,
            "Stopped repeated read-only checkpoint loop and returning summary."
        )

        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 2, "Third repeated read-only checkpoint call should be prevented")
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        return ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_toolloop_harness_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
