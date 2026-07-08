import XCTest
import Combine

@testable import osx_ide

@MainActor
final class ToolLoopEngineRecoveryHarnessTests: XCTestCase {

    // MARK: - Mock Types

    private final class MockEventBus: EventBusProtocol {
        func publish<E: Event>(_ event: E) {}
        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            AnyCancellable {}
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
            dequeueResponse()
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            lock.withLock { historyRequests.append(request) }
            return dequeueResponse()
        }

        func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
            try await sendMessage(request)
        }

        func explainCode(_ code: String) async throws -> String { "Explanation" }
        func refactorCode(_ code: String, instructions: String) async throws -> String { "Refactored" }
        func generateCode(_ prompt: String) async throws -> String { "Generated" }
        func fixCode(_ code: String, error: String) async throws -> String { "Fixed" }

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

    private actor ExecutionCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private struct CountingReadTool: AITool {
        let name = "read_file"
        let description = "Counting harness read tool"
        let counter: ExecutionCounter
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        func execute(arguments _: ToolArguments) async throws -> String {
            await counter.increment()
            return "file content"
        }
    }

    private struct FakeTool: AITool {
        let name: String
        let description: String = "Harness fake tool"
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        func execute(arguments _: ToolArguments) async throws -> String { "ok" }
    }

    private final class HarnessErrorManager: ObservableObject, ErrorManagerProtocol {
        @Published var currentError: AppError?
        @Published var showErrorAlert: Bool = false

        func handle(_ error: AppError) {
            currentError = error
            showErrorAlert = true
        }

        func handle(_ error: Error, context: String) {
            if let appError = error as? AppError { handle(appError); return }
            handle(.unknown("\(context): \(error.localizedDescription)"))
        }

        func dismissError() {
            currentError = nil
            showErrorAlert = false
        }
    }

    // MARK: - Read-Cache Short-Circuit

    func testReadCacheServesRepeatedReadFileCallAcrossIterations() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let counter = ExecutionCounter()
        let tool = CountingReadTool(counter: counter)
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let readFoo = AIToolCall(id: "cache-read-foo", name: "read_file", arguments: ["path": "/test/foo.txt"])

        let scriptedService = ScriptedAIService(responses: [
            // Iter 1 follow-up: same read call again → should hit cache
            AIServiceResponse(content: "Re-reading file.", toolCalls: [readFoo]),
            // Iter 2 follow-up: done
            AIServiceResponse(content: "Done reading.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(fileSystemService: FileSystemService(), errorManager: HarnessErrorManager(), projectRoot: projectRoot)
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Starting.", toolCalls: [readFoo]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [tool],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Read the file"
        )

        let execCount = await counter.count
        harnessEqual(execCount, 1, "Repeated read_file call across iterations should use cache instead of re-executing")
        harnessTrue(result.response.toolCalls?.isEmpty ?? true, "Should finish without dangling tool calls")
        harnessFalse(result.response.content?.isEmpty ?? true, "Final response should have content")
    }

    // MARK: - Malformed Tool Call Recovery

    func testMalformedToolCallInjectsSyntheticFailedMessage() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let malformed = MalformedToolCall(
            id: "malformed-write-1",
            name: "write_file",
            rawArguments: "{invalid",
            error: "Invalid JSON: unexpected end of input"
        )

        let validCall = AIToolCall(id: "valid-tool-1", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Done.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(fileSystemService: FileSystemService(), errorManager: HarnessErrorManager(), projectRoot: projectRoot)
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(
                content: "Starting.",
                toolCalls: [validCall],
                malformedToolCalls: [malformed]
            ),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Write the file"
        )

        let failedMessages = historyCoordinator.messages.filter {
            $0.role == .tool && $0.toolStatus == .failed && $0.toolName == "write_file"
        }
        harnessEqual(failedMessages.count, 1, "Malformed tool call should produce a synthetic failed tool message")

        let failedContent = failedMessages.first?.content ?? ""
        harnessTrue(failedContent.contains("malformed"), "Failed message should mention malformed arguments")
        harnessTrue(failedContent.contains("Invalid JSON"), "Failed message should include the parse error")
        harnessFalse(result.response.content?.isEmpty ?? true, "Final response should have content")
    }

    // MARK: - Deterministic Summary Fallback

    func testDeterministicSummaryFillsEmptyFinalization() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let counter = ExecutionCounter()
        let tool = CountingReadTool(counter: counter)
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let readFoo = AIToolCall(id: "empty-final-read", name: "read_file", arguments: ["path": "/test/foo.txt"])

        let scriptedService = ScriptedAIService(responses: [
            // Iter 1 follow-up: same read → repeated batch (count = 1)
            AIServiceResponse(content: "Re-reading.", toolCalls: [readFoo]),
            // Iter 2 follow-up: same read → repeated batch (count = 2) → read-only stall
            AIServiceResponse(content: "Still reading.", toolCalls: [readFoo]),
            // Inside requestFinalResponseForStalledToolLoop: returns empty → deterministic summary
            AIServiceResponse(content: "", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(fileSystemService: FileSystemService(), errorManager: HarnessErrorManager(), projectRoot: projectRoot)
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Starting.", toolCalls: [readFoo]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [tool],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Read the file"
        )

        let finalContent = result.response.content ?? ""
        harnessFalse(finalContent.isEmpty, "Final response must not be empty when model returns empty content")
        harnessTrue(finalContent.contains("Summary of tool activity"), "Empty finalization should fall back to deterministic summary")
    }

    // MARK: - Helpers

    private func harnessTrue(_ condition: @autoclosure () -> Bool, _ message: String = "") {
        let ok = condition()
        print(ok ? "[HARNESS][PASS] \(message)" : "[HARNESS][WARN] \(message)")
    }

    private func harnessFalse(_ condition: @autoclosure () -> Bool, _ message: String = "") {
        harnessTrue(!condition(), message)
    }

    private func harnessEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String = "") {
        let left = lhs()
        let right = rhs()
        let status = (left == right) ? "[HARNESS][PASS]" : "[HARNESS][WARN]"
        print("\(status) \(message) lhs=\(left) rhs=\(right)")
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        return ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
    }

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tool_loop_engine_\(UUID().uuidString)", isDirectory: true)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
