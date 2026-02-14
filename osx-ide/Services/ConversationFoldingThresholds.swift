import Foundation

public struct ConversationFoldingThresholds: Sendable {
    public let maxMessageCount: Int
    public let maxContentCharacters: Int
    public let preserveMostRecentMessages: Int

    public init(maxMessageCount: Int = 20, maxContentCharacters: Int = 8_000, preserveMostRecentMessages: Int = 8) {
        self.maxMessageCount = maxMessageCount
        self.maxContentCharacters = maxContentCharacters
        self.preserveMostRecentMessages = preserveMostRecentMessages
    }
}
