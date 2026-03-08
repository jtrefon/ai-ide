import XCTest
@testable import osx_ide

@MainActor
final class ModelRoutingAIServiceTests: XCTestCase {
    private final class SpyAIService: AIService, @unchecked Sendable {
        var sendMessageWithProjectRootCallCount = 0
        var sendHistoryCallCount = 0
        var sendStreamingCallCount = 0
        var lastMessageRequest: AIServiceMessageWithProjectRootRequest?
        var lastHistoryRequest: AIServiceHistoryRequest?
        var streamingResponse = AIServiceResponse(content: "streaming", toolCalls: nil)
        var response = AIServiceResponse(content: "ok", toolCalls: nil)

        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            sendMessageWithProjectRootCallCount += 1
            lastMessageRequest = request
            return response
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            sendHistoryCallCount += 1
            lastHistoryRequest = request
            return response
        }

        func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
            _ = runId
            sendStreamingCallCount += 1
            lastHistoryRequest = request
            return streamingResponse
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

    private var defaultsSuiteName: String!
    private var settingsStore: SettingsStore!
    private var selectionStore: LocalModelSelectionStore!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ModelRoutingAIServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        settingsStore = SettingsStore(userDefaults: defaults)
        selectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        }
        selectionStore = nil
        settingsStore = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testOfflineAgentHistoryRequestRoutesToLocalService() async throws {
        let openRouterService = SpyAIService()
        let localService = SpyAIService()
        await selectionStore.setOfflineModeEnabled(true)

        let service = ModelRoutingAIService(
            openRouterService: openRouterService,
            localService: localService,
            selectionStore: selectionStore
        )

        let response = try await service.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Create file")],
            context: nil,
            tools: nil,
            mode: .agent,
            projectRoot: nil,
            runId: "run-1",
            stage: .tool_loop,
            conversationId: "conversation-1"
        ))

        XCTAssertEqual(response.content, "ok")
        XCTAssertEqual(localService.sendHistoryCallCount, 1)
        XCTAssertEqual(openRouterService.sendHistoryCallCount, 0)
        XCTAssertEqual(localService.lastHistoryRequest?.mode, .agent)
        XCTAssertEqual(localService.lastHistoryRequest?.stage, .tool_loop)
        XCTAssertEqual(localService.lastHistoryRequest?.conversationId, "conversation-1")
    }

    func testOfflineAgentStreamingRequestRoutesToLocalService() async throws {
        let openRouterService = SpyAIService()
        let localService = SpyAIService()
        localService.streamingResponse = AIServiceResponse(content: "local-stream", toolCalls: nil)
        await selectionStore.setOfflineModeEnabled(true)

        let service = ModelRoutingAIService(
            openRouterService: openRouterService,
            localService: localService,
            selectionStore: selectionStore
        )

        let response = try await service.sendMessageStreaming(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Do work")],
            context: nil,
            tools: nil,
            mode: .agent,
            projectRoot: nil,
            runId: "run-2",
            stage: .initial_response,
            conversationId: "conversation-2"
        ), runId: "run-2")

        XCTAssertEqual(response.content, "local-stream")
        XCTAssertEqual(localService.sendStreamingCallCount, 1)
        XCTAssertEqual(openRouterService.sendStreamingCallCount, 0)
        XCTAssertEqual(localService.lastHistoryRequest?.mode, .agent)
    }

    func testOnlineAgentHistoryRequestStillRoutesToOpenRouter() async throws {
        let openRouterService = SpyAIService()
        let localService = SpyAIService()
        await selectionStore.setOfflineModeEnabled(false)

        let service = ModelRoutingAIService(
            openRouterService: openRouterService,
            localService: localService,
            selectionStore: selectionStore
        )

        let response = try await service.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Create file")],
            context: nil,
            tools: nil,
            mode: .agent,
            projectRoot: nil
        ))

        XCTAssertEqual(response.content, "ok")
        XCTAssertEqual(openRouterService.sendHistoryCallCount, 1)
        XCTAssertEqual(localService.sendHistoryCallCount, 0)
        XCTAssertEqual(openRouterService.lastHistoryRequest?.mode, .agent)
    }
}
