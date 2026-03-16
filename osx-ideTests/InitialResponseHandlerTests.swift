import XCTest
@testable import osx_ide

@MainActor
final class InitialResponseHandlerTests: XCTestCase {
    private final class ScriptedAIService: AIService, @unchecked Sendable {
        private var responses: [AIServiceResponse]
        private(set) var historyRequests: [AIServiceHistoryRequest] = []

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            _ = request
            return AIServiceResponse(content: "", toolCalls: nil)
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            historyRequests.append(request)
            guard !responses.isEmpty else {
                XCTFail("No scripted response remaining")
                return AIServiceResponse(content: "", toolCalls: nil)
            }
            return responses.removeFirst()
        }

        func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
            _ = runId
            return try await sendMessage(request)
        }

        func explainCode(_ code: String) async throws -> String {
            _ = code
            return ""
        }

        func refactorCode(_ code: String, instructions: String) async throws -> String {
            _ = code
            _ = instructions
            return ""
        }

        func generateCode(_ prompt: String) async throws -> String {
            _ = prompt
            return ""
        }

        func fixCode(_ code: String, error: String) async throws -> String {
            _ = code
            _ = error
            return ""
        }
    }

    private struct NoopTool: AITool {
        let name: String = "read_file"
        let description: String = "noop"

        var parameters: [String: Any] {
            ["type": "object", "properties": [:]]
        }

        func execute(arguments: ToolArguments) async throws -> String {
            _ = arguments
            return "ok"
        }
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let manager = ChatHistoryManager()
        let coordinator = ChatHistoryCoordinator(historyManager: manager, projectRoot: projectRoot)
        coordinator.clearConversation()
        return coordinator
    }

    func testAgentInitialResponseForcesFocusedExecutionWhenInitialReplyClaimsWorkWithoutTools() async throws {
        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("initial-response-handler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "I fixed the lint configuration and resolved the issue.", toolCalls: nil),
            AIServiceResponse(
                content: "",
                toolCalls: [AIToolCall(id: "call-1", name: "read_file", arguments: ["path": "package.json"])]
            )
        ])
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: "please fix linter"))

        let handler = InitialResponseHandler(
            aiInteractionCoordinator: AIInteractionCoordinator(
                aiService: scriptedService,
                codebaseIndex: nil,
                eventBus: EventBus()
            ),
            historyCoordinator: historyCoordinator
        )

        let response = try await handler.sendInitialResponse(
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: historyCoordinator.currentConversationId,
            availableTools: [NoopTool()],
            runId: UUID().uuidString,
            userInput: "please fix linter"
        )

        XCTAssertEqual(scriptedService.historyRequests.count, 2)
        XCTAssertEqual(scriptedService.historyRequests.map(\.stage), [.initial_response, .tool_loop])
        XCTAssertEqual(response.toolCalls?.first?.name, "read_file")
    }

    func testAgentInitialResponseUsesAutonomousToolFollowupWhenExecutionRequestStillReturnsNoTools() async throws {
        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("initial-response-handler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "", toolCalls: nil),
            AIServiceResponse(content: "The lint setup is fixed now.", toolCalls: nil),
            AIServiceResponse(
                content: "",
                toolCalls: [AIToolCall(id: "call-2", name: "read_file", arguments: ["path": "package.json"])]
            )
        ])
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: "can you fix it please?"))

        let handler = InitialResponseHandler(
            aiInteractionCoordinator: AIInteractionCoordinator(
                aiService: scriptedService,
                codebaseIndex: nil,
                eventBus: EventBus()
            ),
            historyCoordinator: historyCoordinator
        )

        let response = try await handler.sendInitialResponse(
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: historyCoordinator.currentConversationId,
            availableTools: [NoopTool()],
            runId: UUID().uuidString,
            userInput: "can you fix it please?"
        )

        XCTAssertEqual(scriptedService.historyRequests.count, 3)
        XCTAssertEqual(scriptedService.historyRequests.map(\.stage), [.initial_response, .tool_loop, .tool_loop])
        XCTAssertEqual(response.toolCalls?.first?.name, "read_file")
    }
}
