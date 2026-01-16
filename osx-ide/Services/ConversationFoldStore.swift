import Foundation

public actor ConversationFoldStore {
    private let projectRoot: URL

    public init(projectRoot: URL) {
        self.projectRoot = projectRoot
    }

    public func list(limit: Int = 50) throws -> [ConversationFoldIndexEntry] {
        let entries = try readIndex()
        if entries.count <= limit { return entries }
        return Array(entries.suffix(limit))
    }

    public func read(id: String) throws -> String {
        let url = contentURL(id: id)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func write(summary: String, content: String) throws -> ConversationFoldIndexEntry {
        let id = UUID().uuidString
        let createdAt = Date()
        let entry = ConversationFoldIndexEntry(id: id, summary: summary, createdAt: createdAt)

        try ensureDirectories()
        try content.write(to: contentURL(id: id), atomically: true, encoding: .utf8)

        var entries = (try? readIndex()) ?? []
        entries.append(entry)
        try writeIndex(entries)

        return entry
    }

    private func ensureDirectories() throws {
        let dir = foldsDirectoryURL()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }

    private func foldsDirectoryURL() -> URL {
        projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("folds", isDirectory: true)
    }

    private func indexURL() -> URL {
        foldsDirectoryURL().appendingPathComponent("index.json")
    }

    private func contentURL(id: String) -> URL {
        foldsDirectoryURL().appendingPathComponent("\(id).txt")
    }

    private func readIndex() throws -> [ConversationFoldIndexEntry] {
        let url = indexURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ConversationFoldIndexEntry].self, from: data)
    }

    private func writeIndex(_ entries: [ConversationFoldIndexEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: indexURL(), options: Data.WritingOptions.atomic)
    }
}
