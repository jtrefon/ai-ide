import Foundation

public actor CrashReporter: CrashReporting {
    public static let shared = CrashReporter()

    private let sessionId: String
    private let iso = ISO8601DateFormatter()
    private let encoder: JSONEncoder

    private var baseLogsDir: URL
    private var appCrashLogFileURL: URL
    private var projectCrashLogFileURL: URL?

    public init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId

        let enc = JSONEncoder()
        enc.outputFormatting = []
        self.encoder = enc

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        self.baseLogsDir = appSupport.appendingPathComponent("osx-ide/Logs", isDirectory: true)

        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let datedDir = baseLogsDir.appendingPathComponent(String(date), isDirectory: true)
        self.appCrashLogFileURL = datedDir.appendingPathComponent("crash.ndjson")
    }

    public func setProjectRoot(_ root: URL) async {
        let ideDir = root.appendingPathComponent(".ide", isDirectory: true)
        let logsDir = ideDir.appendingPathComponent("logs", isDirectory: true)
        self.projectCrashLogFileURL = logsDir.appendingPathComponent("crash.ndjson")
    }

    public func capture(
        _ error: Error,
        context: CrashReportContext,
        metadata: [String: String] = [:],
        file: String,
        function: String,
        line: Int
    ) async {
        let event = CrashReportEvent(
            timestamp: iso.string(from: Date()),
            session: sessionId,
            operation: context.operation,
            errorType: String(reflecting: type(of: error)),
            errorDescription: error.localizedDescription,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        )

        await append(event)
    }

    private func append(_ event: CrashReportEvent) async {
        do {
            let data = try encoder.encode(event)
            var lineData = Data()
            lineData.append(data)
            lineData.append(Data("\n".utf8))

            try ensureDirectoryExists(for: appCrashLogFileURL)
            try append(line: lineData, to: appCrashLogFileURL)

            if let projectCrashLogFileURL {
                try ensureDirectoryExists(for: projectCrashLogFileURL)
                try append(line: lineData, to: projectCrashLogFileURL)
            }
        } catch {
            return
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

    private func ensureDirectoryExists(for fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
}
