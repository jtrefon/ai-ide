import XCTest
@testable import osx_ide

@MainActor
final class FinalResponseHandlerTests: XCTestCase {
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

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let manager = ChatHistoryManager()
        let coordinator = ChatHistoryCoordinator(historyManager: manager, projectRoot: projectRoot)
        coordinator.clearConversation()
        return coordinator
    }

    private func makeProjectRoot() throws -> URL {
        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("final-response-handler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        return projectRoot
    }

    private func makeToolMessage(
        name: String,
        status: ToolExecutionStatus = .completed,
        targetFile: String? = nil,
        toolCallId: String
    ) -> ChatMessage {
        ChatMessage(
            role: .tool,
            content: "{\"status\":\"\(status.rawValue)\",\"message\":\"ok\",\"toolName\":\"\(name)\",\"toolCallId\":\"\(toolCallId)\",\"targetFile\":\"\(targetFile ?? "")\"}",
            tool: ChatMessageToolContext(
                toolName: name,
                toolStatus: status,
                target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCallId)
            )
        )
    }

    func testFinalResponseAcceptsShortConcreteSummaryFromFollowup() async throws {
        let projectRoot = try makeProjectRoot()
        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Created output.txt with HELLO WORLD.", toolCalls: nil)
        ])
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: "create output.txt"))

        let handler = FinalResponseHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: AIInteractionCoordinator(
                aiService: scriptedService,
                codebaseIndex: nil,
                eventBus: EventBus()
            )
        )

        let result = try await handler.requestFinalResponseIfNeeded(
            response: AIServiceResponse(content: "", toolCalls: nil),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            toolResults: [
                makeToolMessage(name: "write_file", targetFile: "output.txt", toolCallId: "call-1")
            ],
            runId: UUID().uuidString,
            conversationId: historyCoordinator.currentConversationId
        )

        XCTAssertEqual(result.content, "Created output.txt with HELLO WORLD.")
        XCTAssertEqual(scriptedService.historyRequests.count, 1)
        XCTAssertEqual(scriptedService.historyRequests.first?.stage, .final_response)
    }

    func testChatReadOnlyFallbackUsesNaturalLanguageInsteadOfControllerTemplate() async throws {
        let projectRoot = try makeProjectRoot()
        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "", toolCalls: nil),
            AIServiceResponse(content: "continuing", toolCalls: nil)
        ])
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: "review dashboard"))

        let handler = FinalResponseHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: AIInteractionCoordinator(
                aiService: scriptedService,
                codebaseIndex: nil,
                eventBus: EventBus()
            )
        )

        let result = try await handler.requestFinalResponseIfNeeded(
            response: AIServiceResponse(content: "", toolCalls: nil),
            explicitContext: nil,
            mode: .chat,
            projectRoot: projectRoot,
            toolResults: [
                makeToolMessage(name: "read_file", targetFile: "src/components/Dashboard.tsx", toolCallId: "call-2"),
                makeToolMessage(name: "list_files", targetFile: nil, toolCallId: "call-3")
            ],
            runId: UUID().uuidString,
            conversationId: historyCoordinator.currentConversationId
        )

        let content = result.content ?? ""
        XCTAssertTrue(content.contains("Dashboard.tsx"))
        XCTAssertFalse(content.contains("Objective:"))
        XCTAssertFalse(content.contains("Work performed:"))
        XCTAssertFalse(content.contains("No plan on record"))
        XCTAssertFalse(content.contains("reliable final summary"))
    }
}
