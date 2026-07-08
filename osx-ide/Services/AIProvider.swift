import Foundation

public enum AIProviderID: String, CaseIterable, Sendable, Equatable {
    case openRouter
    case alibabaCloud
    case kiloCode
    case deepSeek
    case openCodeGo
    case openCodeGoSubscription
    case local

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .alibabaCloud: return "Alibaba Cloud"
        case .kiloCode: return "Kilo Code"
        case .deepSeek: return "DeepSeek"
        case .openCodeGo: return "OpenCode Go"
        case .openCodeGoSubscription: return "OpenCode Go (Subscription)"
        case .local: return "Local Model"
        }
    }
}

public struct ProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let chat = ProviderCapabilities(rawValue: 1 << 0)
    public static let streaming = ProviderCapabilities(rawValue: 1 << 1)
    public static let streamingWithTools = ProviderCapabilities(rawValue: 1 << 2)
    public static let nativeReasoning = ProviderCapabilities(rawValue: 1 << 3)
    public static let toolCalls = ProviderCapabilities(rawValue: 1 << 4)
    public static let fim = ProviderCapabilities(rawValue: 1 << 5)
    public static let embeddings = ProviderCapabilities(rawValue: 1 << 6)
    public static let accountBalance = ProviderCapabilities(rawValue: 1 << 7)
    public static let requiresReasoningEcho = ProviderCapabilities(rawValue: 1 << 8)

    public static let allChat: ProviderCapabilities = [.chat, .streaming, .streamingWithTools, .toolCalls, .nativeReasoning]
    public static let allFIM: ProviderCapabilities = [.fim]
    public static let allEmbeddings: ProviderCapabilities = [.embeddings]
}

public struct ProviderConfiguration: Sendable, Equatable {
    public let providerID: AIProviderID
    public let apiEndpoint: URL
    public let capabilities: ProviderCapabilities
    public let defaultModel: String
    public let supportsNativeReasoning: Bool
    public let requiresReasoningEcho: Bool
    public let maxOutputTokens: Int

    public init(
        providerID: AIProviderID,
        apiEndpoint: URL,
        capabilities: ProviderCapabilities,
        defaultModel: String,
        supportsNativeReasoning: Bool = true,
        requiresReasoningEcho: Bool = false,
        maxOutputTokens: Int = 4096
    ) {
        self.providerID = providerID
        self.apiEndpoint = apiEndpoint
        self.capabilities = capabilities
        self.defaultModel = defaultModel
        self.supportsNativeReasoning = supportsNativeReasoning
        self.requiresReasoningEcho = requiresReasoningEcho
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct UsageInfo: Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let costMicrodollars: Int?
    public let accountBalanceMicrodollars: Int?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        costMicrodollars: Int? = nil,
        accountBalanceMicrodollars: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.costMicrodollars = costMicrodollars
        self.accountBalanceMicrodollars = accountBalanceMicrodollars
    }
}
