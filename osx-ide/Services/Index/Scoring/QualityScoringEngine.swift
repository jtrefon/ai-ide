import Foundation

public final class QualityScoringEngine: @unchecked Sendable {
    private let scorers: [CodeLanguage: any QualityScorer]
    private let context: QualityScoringContext

    public init(projectRoot: URL, scorers: [any QualityScorer]) {
        var map: [CodeLanguage: any QualityScorer] = [:]
        for scorer in scorers {
            map[scorer.language] = scorer
        }
        self.scorers = map
        self.context = QualityScoringContext(projectRoot: projectRoot)
    }

    public func score(language: CodeLanguage, path: String, content: String) async -> QualityAssessment {
        if let scorer = scorers[language] {
            return await scorer.scoreFile(path: path, content: content, context: context)
        }

        let breakdown = QualityBreakdown(categoryScores: [
            .readability: 50,
            .complexity: 50,
            .maintainability: 50,
            .correctness: 50,
            .architecture: 50
        ])

        return QualityAssessment(
            entityType: .file,
            entityName: path,
            language: language,
            score: 50,
            breakdown: breakdown,
            issues: [
                QualityIssue(
                    severity: .info,
                    category: .maintainability,
                    message: "No scorer registered for language: \(language.rawValue)"
                )
            ],
            children: []
        )
    }
}
