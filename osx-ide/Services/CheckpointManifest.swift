import Foundation

public struct CheckpointManifest: Codable, Sendable {
    public let id: String
    public let createdAt: Date
    public let entries: [CheckpointEntry]

    public init(id: String, createdAt: Date, entries: [CheckpointEntry]) {
        self.id = id
        self.createdAt = createdAt
        self.entries = entries
    }
}
