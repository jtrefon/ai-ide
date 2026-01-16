import Foundation

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
