import Foundation

public actor AIToolTraceLogger {
    public static let shared = AIToolTraceLogger()

    private let sessionId: String
    private let encoder: JSONEncoder

    private var projectLogFileURL: URL?

    public init(sessionId: String = UUID().uuidString, logDirectory: URL? = nil) {
        self.sessionId = sessionId

        let enc = JSONEncoder()
        enc.outputFormatting = []
        self.encoder = enc

        if let logDirectory {
            self.projectLogFileURL = logDirectory.appendingPathComponent("ai-trace.ndjson")
        }
    }

    public func setProjectRoot(_ projectRoot: URL) {
        let ideDir = projectRoot.appendingPathComponent(".ide", isDirectory: true)
        let logsDir = ideDir.appendingPathComponent("logs", isDirectory: true)
        self.projectLogFileURL = logsDir.appendingPathComponent("ai-trace.ndjson")
    }

    public func log(type: String, data: [String: Any] = [:], file: String = #fileID, line: Int = #line) {
        do {
            guard let logFileURL = projectLogFileURL else { return }

            try ensureDirectoryExists(for: logFileURL)

            let payload: [String: Any] = [
                "ts": ISO8601DateFormatter().string(from: Date()),
                "session": sessionId,
                "type": type,
                "file": file,
                "line": line,
                "data": data
            ]

            let json = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard var line = String(data: json, encoding: .utf8) else { return }
            line.append("\n")

            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logFileURL, options: [.atomic])
            }
        } catch {
        }
    }

    public func currentLogFilePath() -> String {
        return projectLogFileURL?.path ?? "no log file configured"
    }

    private func ensureDirectoryExists(for fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
}
