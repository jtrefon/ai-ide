import Foundation

public enum QualityEntityType: String, Codable, Sendable {
    case file
    case type
    case function
}

public enum QualityCategory: String, Codable, CaseIterable, Sendable {
    case readability
    case complexity
    case maintainability
    case correctness
    case architecture
}

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

public struct QualityBreakdown: Codable, Sendable {
    public let categoryScores: [String: Double]
    public let metrics: [String: Double]

    public init(categoryScores: [QualityCategory: Double], metrics: [String: Double] = [:]) {
        self.categoryScores = Dictionary(uniqueKeysWithValues: categoryScores.map { ($0.key.rawValue, $0.value) })
        self.metrics = metrics
    }

    public init(categoryScores: [String: Double], metrics: [String: Double] = [:]) {
        self.categoryScores = categoryScores
        self.metrics = metrics
    }
}

public struct QualityAssessment: Codable, Sendable {
    public let entityType: QualityEntityType
    public let entityName: String
    public let language: CodeLanguage
    public let score: Double
    public let breakdown: QualityBreakdown
    public let issues: [QualityIssue]
    public let children: [QualityAssessment]

    public init(
        entityType: QualityEntityType,
        entityName: String,
        language: CodeLanguage,
        score: Double,
        breakdown: QualityBreakdown,
        issues: [QualityIssue] = [],
        children: [QualityAssessment] = []
    ) {
        self.entityType = entityType
        self.entityName = entityName
        self.language = language
        self.score = score
        self.breakdown = breakdown
        self.issues = issues
        self.children = children
    }
}
