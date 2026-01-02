import Foundation

public actor AIToolTraceLogger {
    public static let shared = AIToolTraceLogger()

    private let sessionId: String
    private let logFileURL: URL

    public init(sessionId: String = UUID().uuidString, logDirectory: URL? = nil) {
        self.sessionId = sessionId

        let dir: URL
        if let logDirectory {
            dir = logDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            dir = appSupport.appendingPathComponent("osx-ide/Logs", isDirectory: true)
        }

        let date = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        self.logFileURL = dir.appendingPathComponent("ai-trace-\(date).ndjson")
    }

    public func log(type: String, data: [String: Any] = [:], file: String = #fileID, line: Int = #line) {
        do {
            try ensureDirectoryExists()

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
            // Intentionally swallow logging errors to avoid impacting app behavior.
        }
    }

    public func currentLogFilePath() -> String {
        return logFileURL.path
    }

    private func ensureDirectoryExists() throws {
        let dir = logFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
}
