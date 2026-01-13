import XCTest

@testable import osx_ide

@MainActor
final class ConversationSendCoordinatorTests: XCTestCase {
    private final class SequenceAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [AIServiceResponse]

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(
            _ message: String,
            context: String?,
            tools: [AITool]?,
            mode: AIMode?
        ) async throws -> AIServiceResponse {
            _ = message
            _ = context
            _ = tools
            _ = mode
            return dequeueResponse()
        }

        func sendMessage(
            _ message: String,
            context: String?,
            tools: [AITool]?,
            mode: AIMode?,
            projectRoot: URL?
        ) async throws -> AIServiceResponse {
            _ = message
            _ = context
            _ = tools
            _ = mode
            _ = projectRoot
            return dequeueResponse()
        }

        func sendMessage(
            _ messages: [ChatMessage],
            context: String?,
            tools: [AITool]?,
            mode: AIMode?,
            projectRoot: URL?
        ) async throws -> AIServiceResponse {
            _ = messages
            _ = context
            _ = tools
            _ = mode
            _ = projectRoot
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
                return AIServiceResponse(content: "(no more responses)", toolCalls: nil)
            }
            return responses.removeFirst()
        }
    }

    private struct FakeTool: AITool, @unchecked Sendable {
        let name: String
        let description: String = "fake"
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        let response: String

        func execute(arguments _: ToolArguments) async throws -> String {
            response
        }
    }

    func testSendExecutesToolLoopAndAppendsFinalAssistantMessage() async throws {
        let toolReasoningPrefix =
            "<ide_reasoning>Analyze: Details\nResearch: Details\nPlan: Details\n" +
            "Reflect: Details</ide_reasoning>"
        let toolCallId = UUID().uuidString
        let toolCalls = [
            AIToolCall(id: toolCallId, name: "fake_tool", arguments: ["a": 1])
        ]

        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: toolReasoningPrefix + "Call tool", toolCalls: toolCalls),
            AIServiceResponse(content: toolReasoningPrefix + "Done", toolCalls: nil)
        ])

        let historyManager = ChatHistoryManager()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyCoordinator = ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)

        historyCoordinator.append(ChatMessage(role: .user, content: "Hello"))

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: aiService, codebaseIndex: nil)

        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)

        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(
            userInput: "Hello",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: historyCoordinator.currentConversationId,
            availableTools: [FakeTool(name: "fake_tool", response: "ok")],
            cancelledToolCallIds: { [] }
        )

        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && $0.toolCalls?.isEmpty == false })
        )

        let toolMessages = historyCoordinator.messages.filter {
            $0.role == .tool && $0.toolCallId == toolCallId
        }

        let observedToolMessages = historyCoordinator.messages
            .filter { $0.role == .tool }
            .map {
                "\($0.toolName ?? "nil"):" +
                    "\($0.toolStatus?.rawValue ?? "nil"):" +
                    "\($0.toolCallId ?? "nil")"
            }

        XCTAssertFalse(
            toolMessages.isEmpty,
            "Expected tool messages for toolCallId=\(toolCallId). " +
                "Observed tool messages: \(observedToolMessages)"
        )

        let observedToolStatuses = toolMessages.map {
            "\($0.toolName ?? "nil"):" +
                "\($0.toolStatus?.rawValue ?? "nil")"
        }

        XCTAssertTrue(
            toolMessages.contains(where: { $0.toolStatus == .completed }),
            "Expected at least one completed tool message for toolCallId=\(toolCallId). " +
                "Observed: \(observedToolStatuses)"
        )
        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && $0.content.contains("Done") })
        )
    }
}
