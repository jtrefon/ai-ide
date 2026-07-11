import Foundation

/// How the conversation context is bounded for the LLM request.
///
/// - `compaction`: Summarise older turns via a `.checkpoint` node; the request
///   projection drops everything before the latest checkpoint. Fits smaller
///   windows well but loses detail.
/// - `slidingWindow`: Keep the full immutable chain; the model receives all
///   committed turns up to its natural window limit. Best for large-window
///   models with strong prefix caching (Claude, GPT-5.x) — the cached system
///   prefix stays warm regardless of how many committed turns follow.
public enum ContextStrategy: String, Sendable, Codable {
    case compaction
    case slidingWindow
}

/// Capabilities and recommended strategy for a given model or model family.
/// Used to decide at runtime whether to compact or let the full window through.
public struct ModelContextProfile: Sendable {
    public let modelID: String
    public let windowSize: Int
    public let supportsPrefixCache: Bool

    /// The strategy that best suits this model. The app uses this as the
    /// default but the user/coordinator may override via `ChatHistoryCoordinator.setStrategy(_:)`.
    public let defaultStrategy: ContextStrategy

    public init(
        modelID: String,
        windowSize: Int,
        supportsPrefixCache: Bool,
        defaultStrategy: ContextStrategy
    ) {
        self.modelID = modelID
        self.windowSize = windowSize
        self.supportsPrefixCache = supportsPrefixCache
        self.defaultStrategy = defaultStrategy
    }
}

// MARK: — Registry

extension ModelContextProfile {
    /// Known model profiles. Keys are prefix-matched against the provider's
    /// model string (e.g. `"anthropic/claude-sonnet-4-2025-01-01"` matches
    /// `"anthropic/claude-sonnet-4"`).
    ///
    /// Models with large context windows **and** prefix-cache support default to
    /// `slidingWindow` — keep the full chain and let the cache handle the prefix.
    /// Everything else defaults to `compaction`.
    public static let registry: [String: ModelContextProfile] = [
        "anthropic/claude-sonnet-4":
            .init(modelID: "anthropic/claude-sonnet-4", windowSize: 200_000, supportsPrefixCache: true, defaultStrategy: .slidingWindow),
        "anthropic/claude-haiku-3":
            .init(modelID: "anthropic/claude-haiku-3", windowSize: 200_000, supportsPrefixCache: true, defaultStrategy: .slidingWindow),
        "openai/gpt-4o":
            .init(modelID: "openai/gpt-4o", windowSize: 128_000, supportsPrefixCache: true, defaultStrategy: .slidingWindow),
        "openai/gpt-5":
            .init(modelID: "openai/gpt-5", windowSize: 128_000, supportsPrefixCache: true, defaultStrategy: .slidingWindow),
        "deepseek/deepseek":
            .init(modelID: "deepseek/deepseek", windowSize: 64_000, supportsPrefixCache: true, defaultStrategy: .compaction),
    ]

    /// Safe fallback when no specific profile is registered.
    public static let `default` = ModelContextProfile(
        modelID: "unknown",
        windowSize: 32_000,
        supportsPrefixCache: false,
        defaultStrategy: .compaction
    )

    /// Lookup a profile by prefix-matching against the registry keys.
    /// Returns the default profile when no key matches.
    public static func profile(for modelID: String) -> ModelContextProfile {
        let lower = modelID.lowercased()
        for (key, profile) in registry where lower.hasPrefix(key) {
            return profile
        }
        return `default`
    }
}
