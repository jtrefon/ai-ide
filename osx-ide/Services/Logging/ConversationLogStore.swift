import Foundation

public struct ConversationLogEvent: Codable, Sendable {
    public let ts: String
    public let session: String
    public let conversationId: String
    public let type: String
    public let data: [String: LogValue]?
}

public actor ConversationLogStore {
    public static let shared = ConversationLogStore()

    private let iso = ISO8601DateFormatter()

    private var projectRoot: URL?

    public func setProjectRoot(_ root: URL) {
        self.projectRoot = root
    }

    public func conversationsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let base = appSupport.appendingPathComponent("osx-ide/Logs", isDirectory: true)
        let date = iso.string(from: Date()).prefix(10)
        return base
            .appendingPathComponent(String(date), isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
    }

    public func projectConversationsDirectory() -> URL? {
        guard let projectRoot else { return nil }
        return projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
    }

    private func conversationLogFileURL(conversationId: String) -> URL {
        conversationsDirectory().appendingPathComponent("\(conversationId).ndjson")
    }

    private func projectConversationLogFileURL(conversationId: String) -> URL? {
        projectConversationsDirectory()?.appendingPathComponent("\(conversationId).ndjson")
    }

    public func append(
        conversationId: String,
        type: String,
        data: [String: Any]? = nil
    ) async {
        let sessionId = await AppLogger.shared.currentSessionId()
        let event = ConversationLogEvent(
            ts: iso.string(from: Date()),
            session: sessionId,
            conversationId: conversationId,
            type: type,
            data: data?.mapValues { LogValue.from($0) }
        )

        do {
            let dir = conversationsDirectory()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = conversationLogFileURL(conversationId: conversationId)
            let json = try JSONEncoder().encode(event)
            var line = Data()
            line.append(json)
            line.append(Data("\n".utf8))

            try append(line: line, to: fileURL)

            if let projectDir = projectConversationsDirectory(), let projectFileURL = projectConversationLogFileURL(conversationId: conversationId) {
                try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
                try append(line: line, to: projectFileURL)
            }
        } catch {
        }
    }

    private func append(line: Data, to fileURL: URL) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: fileURL, options: [.atomic])
        }
    }
}
