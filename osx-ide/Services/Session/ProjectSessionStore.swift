import Foundation

public actor ProjectSessionStore {
    public enum StoreError: Error {
        case missingProjectRoot
    }

    private var projectRoot: URL?

    public init() {}

    public func setProjectRoot(_ root: URL) {
        projectRoot = root
    }

    public func load() throws -> ProjectSession? {
        guard let root = projectRoot else { throw StoreError.missingProjectRoot }
        let url = sessionFileURL(projectRoot: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectSession.self, from: data)
    }

    public func save(_ session: ProjectSession) throws {
        guard let root = projectRoot else { throw StoreError.missingProjectRoot }
        let url = sessionFileURL(projectRoot: root)
        try ensureDirectoryExists(for: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    private func sessionFileURL(projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    private func ensureDirectoryExists(for fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
}
