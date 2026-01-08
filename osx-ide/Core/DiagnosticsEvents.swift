import Foundation

public struct TerminalOutputProducedEvent: Event {
    public let output: String

    public init(output: String) {
        self.output = output
    }
}

public struct DiagnosticsUpdatedEvent: Event {
    public let diagnostics: [Diagnostic]

    public init(diagnostics: [Diagnostic]) {
        self.diagnostics = diagnostics
    }
}

public enum DiagnosticSeverity: String, Sendable {
    case error
    case warning
}

public struct Diagnostic: Identifiable, Hashable, Sendable {
    public let id: String
    public let relativePath: String
    public let line: Int
    public let column: Int?
    public let severity: DiagnosticSeverity
    public let message: String

    public init(relativePath: String, line: Int, column: Int?, severity: DiagnosticSeverity, message: String) {
        self.relativePath = relativePath
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.id = "\(relativePath):\(line):\(column ?? -1):\(severity.rawValue):\(message)"
    }
}
