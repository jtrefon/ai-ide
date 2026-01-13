import Foundation

public struct ConversationIndexEntry: Codable, Sendable {
    public let ts: String
    public let session: String
    public let conversationId: String
    public let mode: String
    public let projectRoot: String?
}

public actor ConversationIndexStore {
    public static let shared = ConversationIndexStore()

    private let iso = ISO8601DateFormatter()

    private var projectRoot: URL?

    public func setProjectRoot(_ root: URL) {
        self.projectRoot = root
    }

    private func appSupportIndexFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let base = appSupport.appendingPathComponent("osx-ide/Logs", isDirectory: true)
        let date = iso.string(from: Date()).prefix(10)
        let conversationsDir = base
            .appendingPathComponent(String(date), isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
        return conversationsDir.appendingPathComponent("index.ndjson")
    }

    private func projectIndexFileURL() -> URL? {
        guard let projectRoot else { return nil }
        return projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent("index.ndjson")
    }

    public func appendStart(conversationId: String, mode: String, projectRootPath: String?) async {
        let sessionId = await AppLogger.shared.currentSessionId()
        let entry = ConversationIndexEntry(
            ts: iso.string(from: Date()),
            session: sessionId,
            conversationId: conversationId,
            mode: mode,
            projectRoot: projectRootPath
        )

        do {
            let json = try JSONEncoder().encode(entry)
            var line = Data()
            line.append(json)
            line.append(Data("\n".utf8))

            let appIndexURL = appSupportIndexFileURL()
            try NDJSONLogFileWriter.ensureDirectoryExists(for: appIndexURL)
            try NDJSONLogFileWriter.append(line: line, to: appIndexURL)

            if let projectIndexURL = projectIndexFileURL() {
                try NDJSONLogFileWriter.ensureDirectoryExists(for: projectIndexURL)
                try NDJSONLogFileWriter.append(line: line, to: projectIndexURL)
            }
        } catch {
            await CrashReporter.shared.capture(
                error,
                context: CrashReportContext(operation: "ConversationIndexStore.appendStart"),
                metadata: ["conversationId": conversationId],
                file: #fileID,
                function: #function,
                line: #line
            )
        }
    }
}
