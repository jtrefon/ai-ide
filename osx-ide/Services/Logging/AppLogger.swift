import Foundation

public enum LogLevel: String, Codable, Sendable {
    case trace
    case debug
    case info
    case warning
    case error
    case critical
}

public enum LogCategory: String, Codable, Sendable {
    case app
    case conversation
    case ai
    case tool
    case eventBus
    case error
}

public enum LogValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: LogValue])
    case array([LogValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode([String: LogValue].self) { self = .object(v); return }
        if let v = try? container.decode([LogValue].self) { self = .array(v); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .bool(let v):
            try container.encode(v)
        case .object(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        case .null:
            try container.encodeNil()
        }
    }

    public static func from(_ value: Any) -> LogValue {
        switch value {
        case let v as String:
            return .string(v)
        case let v as Int:
            return .int(v)
        case let v as Double:
            return .double(v)
        case let v as Bool:
            return .bool(v)
        case let v as [String: Any]:
            return .object(v.mapValues { LogValue.from($0) })
        case let v as [Any]:
            return .array(v.map { LogValue.from($0) })
        default:
            return .null
        }
    }
}

public struct LogRecord: Codable, Sendable {
    public let ts: String
    public let session: String
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let metadata: [String: LogValue]?
    public let file: String
    public let function: String
    public let line: Int
}

public struct LoggingConfiguration: Sendable {
    public var minimumLevel: LogLevel
    public var enableConsole: Bool

    public init(minimumLevel: LogLevel = .info, enableConsole: Bool = true) {
        self.minimumLevel = minimumLevel
        self.enableConsole = enableConsole
    }
}

public actor AppLogger {
    public static let shared = AppLogger()

    private let sessionId: String
    private let encoder: JSONEncoder
    private var config: LoggingConfiguration

    private var baseLogsDir: URL
    private var appLogFileURL: URL
    private var projectLogFileURL: URL?

    public init(
        sessionId: String = UUID().uuidString,
        configuration: LoggingConfiguration = LoggingConfiguration()
    ) {
        self.sessionId = sessionId
        self.config = configuration

        let enc = JSONEncoder()
        enc.outputFormatting = []
        self.encoder = enc

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        self.baseLogsDir = appSupport.appendingPathComponent("osx-ide/Logs", isDirectory: true)

        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let datedDir = baseLogsDir.appendingPathComponent(String(date), isDirectory: true)
        self.appLogFileURL = datedDir.appendingPathComponent("app.ndjson")
    }

    public func updateConfiguration(_ configuration: LoggingConfiguration) {
        self.config = configuration
    }

    public func setProjectRoot(_ projectRoot: URL) {
        let ideDir = projectRoot.appendingPathComponent(".ide", isDirectory: true)
        let logsDir = ideDir.appendingPathComponent("logs", isDirectory: true)
        self.projectLogFileURL = logsDir.appendingPathComponent("app.ndjson")
    }

    public func currentSessionId() -> String {
        sessionId
    }

    public func logsDirectoryPath() -> String {
        baseLogsDir.path
    }

    public func log(
        _ level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: Any]? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard shouldLog(level) else { return }

        let record = LogRecord(
            ts: ISO8601DateFormatter().string(from: Date()),
            session: sessionId,
            level: level,
            category: category,
            message: message,
            metadata: metadata?.mapValues { LogValue.from($0) },
            file: file,
            function: function,
            line: line
        )

        write(record: record)

        if config.enableConsole {
            #if DEBUG
            print("[\(record.level.rawValue.uppercased())][\(record.category.rawValue)] \(record.message)")
            #endif
        }
    }

    public func trace(
        category: LogCategory, 
        message: String, 
        metadata: [String: Any]? = nil, 
        file: String = #fileID, 
        function: String = #function, 
        line: Int = #line
    ) {
        log(
                .trace, 
                category: category, 
                message: message, 
                metadata: metadata, 
                file: file, 
                function: function, 
                line: line
            )
    }

    public func debug(
        category: LogCategory, 
        message: String, 
        metadata: [String: Any]? = nil, 
        file: String = #fileID, 
        function: String = #function, 
        line: Int = #line
    ) {
        log(
                .debug, 
                category: category, 
                message: message, 
                metadata: metadata, 
                file: file, 
                function: function, 
                line: line
            )
    }

    public func info(
        category: LogCategory, 
        message: String, 
        metadata: [String: Any]? = nil, 
        file: String = #fileID, 
        function: String = #function, 
        line: Int = #line
    ) {
        log(.info, category: category, message: message, metadata: metadata, file: file, function: function, line: line)
    }

    public func warning(
        category: LogCategory, 
        message: String, 
        metadata: [String: Any]? = nil, 
        file: String = #fileID, 
        function: String = #function, 
        line: Int = #line
    ) {
        log(
                .warning, 
                category: category, 
                message: message, 
                metadata: metadata, 
                file: file, 
                function: function, 
                line: line
            )
    }

    public func error(
        category: LogCategory, 
        message: String, 
        metadata: [String: Any]? = nil, 
        file: String = #fileID, 
        function: String = #function, 
        line: Int = #line
    ) {
        log(
                .error, 
                category: category, 
                message: message, 
                metadata: metadata, 
                file: file, 
                function: function, 
                line: line
            )
    }

    public func critical(
        category: LogCategory, 
        message: String, 
        metadata: [String: Any]? = nil, 
        file: String = #fileID, 
        function: String = #function, 
        line: Int = #line
    ) {
        log(
                .critical, 
                category: category, 
                message: message, 
                metadata: metadata, 
                file: file, 
                function: function, 
                line: line
            )
    }

    private func shouldLog(_ level: LogLevel) -> Bool {
        let rank: [LogLevel: Int] = [
            .trace: 0,
            .debug: 1,
            .info: 2,
            .warning: 3,
            .error: 4,
            .critical: 5
        ]
        return (rank[level] ?? 999) >= (rank[config.minimumLevel] ?? 999)
    }

    private func write(record: LogRecord) {
        do {
            try ensureDirectoryExists(for: appLogFileURL)
            let data = try encoder.encode(record)
            var line = Data()
            line.append(data)
            line.append(Data("\n".utf8))

            try append(line: line, to: appLogFileURL)
            if let projectLogFileURL {
                try ensureDirectoryExists(for: projectLogFileURL)
                try append(line: line, to: projectLogFileURL)
            }
        } catch {
            Task {
                await CrashReporter.shared.capture(
                    error,
                    context: CrashReportContext(operation: "AppLogger.write"),
                    metadata: nil,
                    file: #fileID,
                    function: #function,
                    line: #line
                )
            }
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
