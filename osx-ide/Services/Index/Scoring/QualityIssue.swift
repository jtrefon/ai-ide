import Foundation

public struct QualityIssue: Codable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case critical
    }

    public let severity: Severity
    public let category: QualityCategory
    public let message: String
    public let line: Int?

    public init(severity: Severity, category: QualityCategory, message: String, line: Int? = nil) {
        self.severity = severity
        self.category = category
        self.message = message
        self.line = line
    }
}
