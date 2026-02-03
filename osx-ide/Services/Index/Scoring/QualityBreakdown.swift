import Foundation

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
