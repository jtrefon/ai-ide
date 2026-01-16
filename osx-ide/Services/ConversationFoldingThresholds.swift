import Foundation

public struct ConversationFoldingThresholds: Sendable {
    public let maxMessageCount: Int
    public let maxContentCharacters: Int
    public let preserveMostRecentMessages: Int

    public init(maxMessageCount: Int = 40, maxContentCharacters: Int = 20_000, preserveMostRecentMessages: Int = 20) {
        self.maxMessageCount = maxMessageCount
        self.maxContentCharacters = maxContentCharacters
        self.preserveMostRecentMessages = preserveMostRecentMessages
    }
}
