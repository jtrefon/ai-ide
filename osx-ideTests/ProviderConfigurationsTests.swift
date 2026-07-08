import XCTest
@testable import osx_ide

final class ProviderConfigurationsTests: XCTestCase {
    func testOpenRouterProviderConfig() {
        let config = OpenRouterProviderConfig()
        XCTAssertEqual(config.providerID, .openRouter)
        XCTAssertEqual(config.providerName, "OpenRouter")
        XCTAssertTrue(config.supportsStreamingWithTools)
        XCTAssertTrue(config.supportsNativeReasoning)
        XCTAssertFalse(config.requiresReasoningEcho)
    }

    func testAlibabaProviderConfig() {
        let config = AlibabaProviderConfig()
        XCTAssertEqual(config.providerID, .alibabaCloud)
        XCTAssertEqual(config.providerName, "Alibaba Cloud")
        XCTAssertFalse(config.supportsStreamingWithTools)
        XCTAssertFalse(config.supportsNativeReasoning)
    }

    func testDeepSeekProviderConfig() {
        let config = DeepSeekProviderConfig()
        XCTAssertEqual(config.providerID, .deepSeek)
        XCTAssertEqual(config.providerName, "DeepSeek")
        XCTAssertTrue(config.supportsStreamingWithTools)
        XCTAssertTrue(config.supportsNativeReasoning)
        XCTAssertTrue(config.requiresReasoningEcho)
    }

    func testKiloCodeProviderConfig() {
        let config = KiloCodeProviderConfig()
        XCTAssertEqual(config.providerID, .kiloCode)
        XCTAssertEqual(config.providerName, "Kilo Code")
        XCTAssertTrue(config.supportsStreamingWithTools)
        XCTAssertTrue(config.supportsNativeReasoning)
        XCTAssertFalse(config.requiresReasoningEcho)

        let context = config.buildRequestContext(baseURL: "https://api.kilo.ai/api/openrouter")
        XCTAssertEqual(context.appName, "Kilo Code")
        XCTAssertEqual(context.referer, "https://kilocode.ai")
    }

    func testOpenCodeGoProviderConfig() {
        let config = OpenCodeGoProviderConfig()
        XCTAssertEqual(config.providerID, .openCodeGo)
        XCTAssertEqual(config.providerName, "OpenCode Go")
        XCTAssertTrue(config.supportsStreamingWithTools)
        XCTAssertTrue(config.supportsNativeReasoning)
    }

    func testOpenCodeGoSubscriptionProviderConfig() {
        let config = OpenCodeGoSubscriptionProviderConfig()
        XCTAssertEqual(config.providerID, .openCodeGoSubscription)
        XCTAssertEqual(config.providerName, "OpenCode Go (Subscription)")
        XCTAssertTrue(config.supportsStreamingWithTools)
        XCTAssertTrue(config.supportsNativeReasoning)
        XCTAssertFalse(config.requiresReasoningEcho)
    }

    func testProviderCapabilitiesOptionSet() {
        let chat = ProviderCapabilities.chat
        let streaming = ProviderCapabilities.streaming
        let both: ProviderCapabilities = [.chat, .streaming]
        XCTAssertTrue(both.contains(.chat))
        XCTAssertTrue(both.contains(.streaming))
        XCTAssertFalse(streaming.contains(.chat))
        XCTAssertTrue(chat.contains(.chat))
    }

    func testAllChatCapabilities() {
        let caps = ProviderCapabilities.allChat
        XCTAssertTrue(caps.contains(.chat))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.streamingWithTools))
        XCTAssertTrue(caps.contains(.toolCalls))
        XCTAssertTrue(caps.contains(.nativeReasoning))
        XCTAssertFalse(caps.contains(.fim))
    }

    func testProviderConfigurationBuilder() {
        let url = URL(string: "https://api.test.com/v1")!
        let config = ProviderConfiguration(
            providerID: .openRouter,
            apiEndpoint: url,
            capabilities: [.chat, .streaming],
            defaultModel: "test-model"
        )
        XCTAssertEqual(config.providerID, .openRouter)
        XCTAssertEqual(config.apiEndpoint, url)
        XCTAssertEqual(config.defaultModel, "test-model")
        XCTAssertTrue(config.capabilities.contains(.chat))
        XCTAssertFalse(config.capabilities.contains(.toolCalls))
    }

    func testRemoteAIProviderToAIProviderID() {
        XCTAssertEqual(RemoteAIProvider.openRouter.toAIProviderID, .openRouter)
        XCTAssertEqual(RemoteAIProvider.alibabaCloud.toAIProviderID, .alibabaCloud)
        XCTAssertEqual(RemoteAIProvider.kiloCode.toAIProviderID, .kiloCode)
        XCTAssertEqual(RemoteAIProvider.deepSeek.toAIProviderID, .deepSeek)
        XCTAssertEqual(RemoteAIProvider.openCodeGo.toAIProviderID, .openCodeGo)
        XCTAssertEqual(RemoteAIProvider.openCodeGoSubscription.toAIProviderID, .openCodeGoSubscription)
    }

    func testAIProviderIDAllCasesCoverage() {
        let allCases = AIProviderID.allCases
        XCTAssertTrue(allCases.contains(.openRouter))
        XCTAssertTrue(allCases.contains(.alibabaCloud))
        XCTAssertTrue(allCases.contains(.kiloCode))
        XCTAssertTrue(allCases.contains(.deepSeek))
        XCTAssertTrue(allCases.contains(.openCodeGo))
        XCTAssertTrue(allCases.contains(.openCodeGoSubscription))
        XCTAssertTrue(allCases.contains(.local))
    }
}
