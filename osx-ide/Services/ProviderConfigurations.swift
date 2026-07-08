import Foundation

// MARK: - OpenRouter

struct OpenRouterProviderConfig: ProviderConfig {
    let providerID: AIProviderID = .openRouter
    let providerName: String = "OpenRouter"
    let capabilities: ProviderCapabilities = [.chat, .streaming, .streamingWithTools, .toolCalls, .nativeReasoning]
    let supportsStreamingWithTools: Bool = true
    let supportsNativeReasoning: Bool = true
    let requiresReasoningEcho: Bool = false
}

// MARK: - Alibaba Cloud

struct AlibabaProviderConfig: ProviderConfig {
    let providerID: AIProviderID = .alibabaCloud
    let providerName: String = "Alibaba Cloud"
    let capabilities: ProviderCapabilities = [.chat, .streaming, .toolCalls]
    let supportsStreamingWithTools: Bool = false
    let supportsNativeReasoning: Bool = false
    let requiresReasoningEcho: Bool = false
}

// MARK: - DeepSeek

struct DeepSeekProviderConfig: ProviderConfig {
    let providerID: AIProviderID = .deepSeek
    let providerName: String = "DeepSeek"
    let capabilities: ProviderCapabilities = [.chat, .streaming, .streamingWithTools, .toolCalls, .nativeReasoning, .accountBalance, .requiresReasoningEcho]
    let supportsStreamingWithTools: Bool = true
    let supportsNativeReasoning: Bool = true
    let requiresReasoningEcho: Bool = true

    func fetchBalance(apiKey: String, baseURL: String, client: OpenRouterAPIClient) async throws -> Int? {
        guard let apiBaseURL = providerAPIBaseURL(from: baseURL) else { return nil }
        guard let balance = try await client.fetchDeepSeekBalance(apiKey: apiKey, apiBaseURL: apiBaseURL) else { return nil }
        return NSDecimalNumber(decimal: balance * Decimal(1_000_000)).intValue
    }

    private func providerAPIBaseURL(from baseURL: String) -> String? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - Kilo Code

struct KiloCodeProviderConfig: ProviderConfig {
    let providerID: AIProviderID = .kiloCode
    let providerName: String = "Kilo Code"
    let capabilities: ProviderCapabilities = [.chat, .streaming, .streamingWithTools, .toolCalls, .nativeReasoning, .accountBalance]
    let supportsStreamingWithTools: Bool = true
    let supportsNativeReasoning: Bool = true
    let requiresReasoningEcho: Bool = false

    func buildRequestContext(baseURL: String) -> OpenRouterAPIClient.RequestContext {
        OpenRouterAPIClient.RequestContext(baseURL: baseURL, appName: "Kilo Code", referer: "https://kilocode.ai")
    }

    func resolvedCostMicrodollars(usage: OpenRouterChatUsage, fallback: Int?) -> Int? {
        if let costMicrodollars = usage.costMicrodollars { return costMicrodollars }
        if let upstreamCost = usage.costDetails?.upstreamInferenceCost {
            return NSDecimalNumber(decimal: upstreamCost * Decimal(1_000_000)).intValue
        }
        if let directCost = usage.cost {
            return NSDecimalNumber(decimal: directCost * Decimal(1_000_000)).intValue
        }
        return fallback
    }

    func fetchBalance(apiKey: String, baseURL: String, client: OpenRouterAPIClient) async throws -> Int? {
        guard let apiBaseURL = kiloAPIBaseURL(from: baseURL) else { return nil }
        guard let balance = try await client.fetchKiloBalance(apiKey: apiKey, apiBaseURL: apiBaseURL) else { return nil }
        return NSDecimalNumber(decimal: balance * Decimal(1_000_000)).intValue
    }

    private func providerAPIBaseURL(from baseURL: String) -> String? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func kiloAPIBaseURL(from baseURL: String) -> String? {
        providerAPIBaseURL(from: baseURL)
    }
}

// MARK: - OpenCode Go Subscription

struct OpenCodeGoSubscriptionProviderConfig: ProviderConfig {
    let providerID: AIProviderID = .openCodeGoSubscription
    let providerName: String = "OpenCode Go (Subscription)"
    let capabilities: ProviderCapabilities = [.chat, .streaming, .streamingWithTools, .toolCalls, .nativeReasoning]
    let supportsStreamingWithTools: Bool = true
    let supportsNativeReasoning: Bool = true
    let requiresReasoningEcho: Bool = false
}

// MARK: - OpenCode Go

struct OpenCodeGoProviderConfig: ProviderConfig {
    let providerID: AIProviderID = .openCodeGo
    let providerName: String = "OpenCode Go"
    let capabilities: ProviderCapabilities = [.chat, .streaming, .streamingWithTools, .toolCalls, .nativeReasoning]
    let supportsStreamingWithTools: Bool = true
    let supportsNativeReasoning: Bool = true
    let requiresReasoningEcho: Bool = false
}
