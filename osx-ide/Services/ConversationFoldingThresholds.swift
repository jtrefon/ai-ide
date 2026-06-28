import Foundation

public struct ConversationFoldingThresholds: Sendable {
    public let maxMessageCount: Int
    public let maxContentCharacters: Int
    public let preserveMostRecentMessages: Int

    /// Default thresholds for regular chat mode.
    public static let chat = ConversationFoldingThresholds(
        maxMessageCount: 40,
        maxContentCharacters: 16_000,
        preserveMostRecentMessages: 12
    )

    /// Higher thresholds for agent/tool-loop mode to avoid folding mid-work.
    public static let agent = ConversationFoldingThresholds(
        maxMessageCount: 80,
        maxContentCharacters: 48_000,
        preserveMostRecentMessages: 24
    )

    /// Thresholds tuned for local MLX models (Gemma 4, 32K context).
    /// Tighter limits to prevent context overflow, with more recent
    /// messages preserved for tool loop continuity.
    public static let localAgent = ConversationFoldingThresholds(
        maxMessageCount: 60,
        maxContentCharacters: 80_000,
        preserveMostRecentMessages: 30
    )

    public init(maxMessageCount: Int = 40, maxContentCharacters: Int = 16_000, preserveMostRecentMessages: Int = 12) {
        self.maxMessageCount = maxMessageCount
        self.maxContentCharacters = maxContentCharacters
        self.preserveMostRecentMessages = preserveMostRecentMessages
    }
}
