import Foundation

public struct MemoryEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let tier: MemoryTier
    public let content: String
    public let category: String
    public let timestamp: Date
    public let protectionLevel: Int

    public init(id: String = UUID().uuidString, tier: MemoryTier, content: String, category: String, timestamp: Date = Date(), protectionLevel: Int = 0) {
        self.id = id
        self.tier = tier
        self.content = content
        self.category = category
        self.timestamp = timestamp
        self.protectionLevel = protectionLevel
    }
}
