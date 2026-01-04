import Foundation

public struct QualityScoringContext: Sendable {
    public let projectRoot: URL

    public init(projectRoot: URL) {
        self.projectRoot = projectRoot
    }
}

public protocol QualityScorer: Sendable {
    var language: CodeLanguage { get }
    func scoreFile(path: String, content: String, context: QualityScoringContext) async -> QualityAssessment
}
