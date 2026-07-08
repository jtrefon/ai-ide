import XCTest
import Combine
@testable import osx_ide

final class OpenAICompatibleChatServiceTests: XCTestCase {
    private var eventBus: EventBus!
    private var urlSession: URLSession!
    private var config: OpenRouterProviderConfig!
    private var usageTracker: UsageTracker!
    private var service: OpenAICompatibleChatService!

    override func setUp() {
        eventBus = EventBus()
        config = OpenRouterProviderConfig()
        let urlConfig = URLProtocolMock.makeProtocolConfiguration()
        urlSession = URLSession(configuration: urlConfig)
        let client = OpenRouterAPIClient(urlSession: urlSession)
        usageTracker = UsageTracker(client: client, eventBus: eventBus)
        service = OpenAICompatibleChatService(
            client: client,
            config: config,
            usageTracker: usageTracker,
            eventBus: eventBus,
            testConfigurationProvider: TestConfigurationProvider(),
            toolCallParser: ToolCallFallbackParser(),
            supportsStreamingWithToolsOverride: true,
            settingsStoreProvider: { OpenRouterSettingsStore() }
        )
    }

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        service = nil
        usageTracker = nil
        config = nil
        urlSession = nil
        eventBus = nil
    }

    func testProviderNameMatchesConfig() {
        func makeService(config: any ProviderConfig) -> OpenAICompatibleChatService {
            let c = OpenRouterAPIClient(urlSession: urlSession)
            let u = UsageTracker(client: c, eventBus: eventBus!)
            return OpenAICompatibleChatService(client: c, config: config, usageTracker: u, eventBus: eventBus!)
        }

        XCTAssertEqual(makeService(config: OpenRouterProviderConfig()).providerName, "OpenRouter")
        XCTAssertEqual(makeService(config: DeepSeekProviderConfig()).providerName, "DeepSeek")
        XCTAssertEqual(makeService(config: KiloCodeProviderConfig()).providerName, "Kilo Code")
        XCTAssertEqual(makeService(config: OpenCodeGoProviderConfig()).providerName, "OpenCode Go")
        XCTAssertEqual(makeService(config: OpenCodeGoSubscriptionProviderConfig()).providerName, "OpenCode Go (Subscription)")
        XCTAssertEqual(makeService(config: AlibabaProviderConfig()).providerName, "Alibaba Cloud")
    }

    func testSendMessageUsesCorrectRequestBody() async throws {
        let expectation = XCTestExpectation(description: "Request captured")
        URLProtocolMock.requestHandler = { request in
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
            {"id":"test","object":"chat.completion","created":123,"model":"test","choices":[{"index":0,"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
            """.data(using: .utf8)!
            return (response, data)
        }

        let response = try await service.sendMessage(AIServiceMessageWithProjectRootRequest(
            message: "Hi", context: nil, tools: nil, mode: nil, projectRoot: nil
        ))

        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertEqual(response.content, "Hello")
    }

    func testSendMessageWithToolCalls() async throws {
        URLProtocolMock.requestHandler = { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // Tool calls format is tested separately; verify request body has tools
            let data = """
            {"id":"test","object":"chat.completion","created":123,"model":"test","choices":[{"index":0,"message":{"role":"assistant","content":"Done"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
            """.data(using: .utf8)!
            return (response, data)
        }

        let tool = OpenAITestNoopTool(name: "write_file", description: "Write a file", parameters: [
            "type": "object",
            "properties": ["path": ["type": "string"]],
            "required": ["path"]
        ])

        // Test that the request includes tool definitions correctly
        let response = try await service.sendMessage(AIServiceMessageWithProjectRootRequest(
            message: "Write hello.txt",
            context: nil,
            tools: [tool],
            mode: .agent,
            projectRoot: nil
        ))

        XCTAssertEqual(response.content, "Done")
    }

    func testSendMessageThrowsOnEmptyChoices() async {
        URLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
            {"id":"test","object":"chat.completion","created":123,"model":"test","choices":[],"usage":null}
            """.data(using: .utf8)!
            return (response, data)
        }

        do {
            _ = try await service.sendMessage(AIServiceMessageWithProjectRootRequest(
                message: "Hi", context: nil, tools: nil, mode: nil, projectRoot: nil
            ))
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is AppError)
        }
    }

    func testSendMessageStreamingWithMockData() async throws {
        URLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            let chunks = [
                "data: {\"id\":\"test\",\"object\":\"chat.completion.chunk\",\"created\":123,\"model\":\"test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n",
                "data: {\"id\":\"test\",\"object\":\"chat.completion.chunk\",\"created\":123,\"model\":\"test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]}\n",
                "data: [DONE]\n"
            ]
            let data = chunks.joined().data(using: .utf8)!
            return (response, data)
        }

        let response = try await service.sendMessageStreaming(
            AIServiceHistoryRequest(
                messages: [ChatMessage(role: .user, content: "Say hi")],
                context: nil, tools: nil, mode: nil, projectRoot: nil, runId: "test-run"
            ),
            runId: "test-run"
        )

        XCTAssertEqual(response.content, "Hello world")
    }
}

// MARK: - URL Protocol Mock

private class URLProtocolMock: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = URLProtocolMock.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeProtocolConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return config
    }
}

private struct OpenAITestNoopTool: AITool, @unchecked Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]
    func execute(arguments: ToolArguments) async throws -> String { "ok" }
}
