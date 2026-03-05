import Foundation

struct RAGEvidenceCandidate: Sendable {
    let id: String
    let type: EvidenceType
    let filePath: String?
    let lineStart: Int?
    let lineEnd: Int?
    let preview: String
    let searchableText: String
    let qualityScore: Double?
    let freshness: Double
}

public struct RAGEvidenceFusionRanker: Sendable {
    public init() {}

    func rank(
        candidates: [RAGEvidenceCandidate],
        userInput: String,
        intent: RetrievalIntent
    ) -> [EvidenceCard] {
        candidates
            .map { candidate in
                makeEvidenceCard(candidate: candidate, userInput: userInput, intent: intent)
            }
            .sorted(by: compare)
    }

    private func makeEvidenceCard(
        candidate: RAGEvidenceCandidate,
        userInput: String,
        intent: RetrievalIntent
    ) -> EvidenceCard {
        let semanticSimilarity = normalizedTokenOverlap(query: userInput, text: candidate.searchableText)
        let intentWeight = intentWeight(for: intent, evidenceType: candidate.type)
        let architectureProximity = normalizedTokenOverlap(query: userInput, text: candidate.filePath ?? "")
        let qualityHotspotBoost = qualityHotspotBoost(for: candidate.qualityScore)
        let recencyBoost = max(0, min(1, candidate.freshness)) * 0.2
        let stalenessPenalty = max(0, 1 - max(0, min(1, candidate.freshness))) * 0.2

        let totalScore = semanticSimilarity * intentWeight
            + architectureProximity
            + qualityHotspotBoost
            + recencyBoost
            - stalenessPenalty

        let components = EvidenceScoreComponents(
            semanticSimilarity: semanticSimilarity,
            intentWeight: intentWeight,
            architectureProximity: architectureProximity,
            qualityHotspotBoost: qualityHotspotBoost,
            recencyBoost: recencyBoost,
            stalenessPenalty: stalenessPenalty
        )

        let confidence = max(0, min(1, (semanticSimilarity + architectureProximity) / 2))

        return EvidenceCard(
            evidenceId: candidate.id,
            type: candidate.type,
            filePath: candidate.filePath,
            lineStart: candidate.lineStart,
            lineEnd: candidate.lineEnd,
            scoreTotal: totalScore,
            scoreComponents: components,
            confidence: confidence,
            freshness: candidate.freshness,
            whySelected: whySelected(intent: intent, candidate: candidate, score: totalScore),
            preview: candidate.preview
        )
    }

    private func compare(_ lhs: EvidenceCard, _ rhs: EvidenceCard) -> Bool {
        if lhs.scoreTotal != rhs.scoreTotal {
            return lhs.scoreTotal > rhs.scoreTotal
        }

        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }

        if lhs.type != rhs.type {
            return lhs.type.rawValue < rhs.type.rawValue
        }

        if (lhs.filePath ?? "") != (rhs.filePath ?? "") {
            return (lhs.filePath ?? "") < (rhs.filePath ?? "")
        }

        if (lhs.lineStart ?? 0) != (rhs.lineStart ?? 0) {
            return (lhs.lineStart ?? 0) < (rhs.lineStart ?? 0)
        }

        return lhs.evidenceId < rhs.evidenceId
    }

    private func intentWeight(for intent: RetrievalIntent, evidenceType: EvidenceType) -> Double {
        switch (intent, evidenceType) {
        case (.bugfix, .symbol), (.bugfix, .segment):
            return 1.4
        case (.feature, .summary), (.feature, .symbol):
            return 1.3
        case (.refactor, .summary), (.refactor, .segment):
            return 1.25
        case (.tests, .test), (.tests, .segment):
            return 1.35
        case (.cleanup, .issue), (.cleanup, .summary):
            return 1.3
        case (.explanation, .summary), (.explanation, .memory):
            return 1.2
        default:
            return 1.0
        }
    }

    private func qualityHotspotBoost(for qualityScore: Double?) -> Double {
        guard let qualityScore else {
            return 0
        }

        let normalizedQuality = max(0, min(100, qualityScore)) / 100
        return (1 - normalizedQuality) * 0.35
    }

    private func normalizedTokenOverlap(query: String, text: String) -> Double {
        let queryTokens = Set(tokenize(query))
        let textTokens = Set(tokenize(text))

        guard !queryTokens.isEmpty, !textTokens.isEmpty else {
            return 0
        }

        let overlap = queryTokens.intersection(textTokens).count
        return Double(overlap) / Double(queryTokens.count)
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map { $0.lowercased() }
            .filter { $0.count >= 3 }
    }

    private func whySelected(intent: RetrievalIntent, candidate: RAGEvidenceCandidate, score: Double) -> String {
        let intentPart = "intent=\(intent.rawValue)"
        let sourcePart = "source=\(candidate.type.rawValue)"
        let scorePart = String(format: "score=%.2f", score)
        return [intentPart, sourcePart, scorePart].joined(separator: ", ")
    }
}
