import Foundation

public struct ConversationFoldResult: Sendable {
    public let entry: ConversationFoldIndexEntry
    public let foldedMessageCount: Int

    public init(entry: ConversationFoldIndexEntry, foldedMessageCount: Int) {
        self.entry = entry
        self.foldedMessageCount = foldedMessageCount
    }
}
