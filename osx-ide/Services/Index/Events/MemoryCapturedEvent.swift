import Foundation

public struct MemoryCapturedEvent: Event {
    public let tier: String
    public let content: String

    public init(tier: String, content: String) {
        self.tier = tier
        self.content = content
    }
}
