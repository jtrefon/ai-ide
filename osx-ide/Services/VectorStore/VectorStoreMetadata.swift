import Foundation

public struct VectorStoreMetadata: Codable, Sendable {
    public struct Entry: Codable, Sendable, Identifiable {
        public let id: String
        public let text: String
        public let source: String
        public let timestamp: Date
        public let category: String?
        public let embeddingModel: String

        public init(
            id: String,
            text: String,
            source: String,
            timestamp: Date = Date(),
            category: String? = nil,
            embeddingModel: String
        ) {
            self.id = id
            self.text = text
            self.source = source
            self.timestamp = timestamp
            self.category = category
            self.embeddingModel = embeddingModel
        }
    }

    private var entries: [String: Entry] = [:]
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func entry(for id: String) -> Entry? {
        entries[id]
    }

    public mutating func add(_ entry: Entry) {
        entries[entry.id] = entry
    }

    public mutating func remove(id: String) {
        entries.removeValue(forKey: id)
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    public var all: [Entry] {
        Array(entries.values)
    }

    public var count: Int {
        entries.count
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    public mutating func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = [:]
            return
        }
        let data = try Data(contentsOf: fileURL)
        entries = try JSONDecoder().decode([String: Entry].self, from: data)
    }
}
