import Foundation

public struct ConversationFoldIndexEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let summary: String
    public let createdAt: Date

    public init(id: String, summary: String, createdAt: Date) {
        self.id = id
        self.summary = summary
        self.createdAt = createdAt
    }
}
