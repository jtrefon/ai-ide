import Foundation

public struct RAGRetrievalRequest: Sendable {
    public let userInput: String
    public let projectRoot: URL?
    public let stage: String?
    public let conversationId: String?

    public init(
        userInput: String,
        projectRoot: URL?,
        stage: String? = nil,
        conversationId: String? = nil
    ) {
        self.userInput = userInput
        self.projectRoot = projectRoot
        self.stage = stage
        self.conversationId = conversationId
    }
}

public enum RetrievalIntent: String, Sendable {
    case bugfix
    case feature
    case refactor
    case explanation
    case tests
    case cleanup
    case other
}

public enum EvidenceType: String, Sendable {
    case summary
    case symbol
    case segment
    case memory
    case issue
    case test
}

public struct EvidenceScoreComponents: Sendable {
    public let semanticSimilarity: Double
    public let intentWeight: Double
    public let architectureProximity: Double
    public let qualityHotspotBoost: Double
    public let recencyBoost: Double
    public let stalenessPenalty: Double

    public init(
        semanticSimilarity: Double,
        intentWeight: Double,
        architectureProximity: Double,
        qualityHotspotBoost: Double,
        recencyBoost: Double,
        stalenessPenalty: Double
    ) {
        self.semanticSimilarity = semanticSimilarity
        self.intentWeight = intentWeight
        self.architectureProximity = architectureProximity
        self.qualityHotspotBoost = qualityHotspotBoost
        self.recencyBoost = recencyBoost
        self.stalenessPenalty = stalenessPenalty
    }

    public static let zero = EvidenceScoreComponents(
        semanticSimilarity: 0,
        intentWeight: 0,
        architectureProximity: 0,
        qualityHotspotBoost: 0,
        recencyBoost: 0,
        stalenessPenalty: 0
    )
}

public struct EvidenceCard: Sendable {
    public let evidenceId: String
    public let type: EvidenceType
    public let filePath: String?
    public let lineStart: Int?
    public let lineEnd: Int?
    public let scoreTotal: Double
    public let scoreComponents: EvidenceScoreComponents
    public let confidence: Double
    public let freshness: Double
    public let whySelected: String
    public let preview: String

    public init(
        evidenceId: String,
        type: EvidenceType,
        filePath: String?,
        lineStart: Int?,
        lineEnd: Int?,
        scoreTotal: Double,
        scoreComponents: EvidenceScoreComponents,
        confidence: Double,
        freshness: Double,
        whySelected: String,
        preview: String
    ) {
        self.evidenceId = evidenceId
        self.type = type
        self.filePath = filePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.scoreTotal = scoreTotal
        self.scoreComponents = scoreComponents
        self.confidence = confidence
        self.freshness = freshness
        self.whySelected = whySelected
        self.preview = preview
    }
}

public struct RAGRetrievalResult: Sendable {
    public let projectOverviewLines: [String]
    public let symbolLines: [String]
    public let memoryLines: [String]
    public let segmentLines: [String]
    public let reuseCandidateLines: [String]
    public let evidenceCards: [EvidenceCard]
    public let intent: RetrievalIntent
    public let retrievalConfidence: Double

    public init(
        projectOverviewLines: [String],
        symbolLines: [String],
        memoryLines: [String],
        segmentLines: [String] = [],
        reuseCandidateLines: [String] = [],
        evidenceCards: [EvidenceCard] = [],
        intent: RetrievalIntent = .other,
        retrievalConfidence: Double = 0
    ) {
        self.projectOverviewLines = projectOverviewLines
        self.symbolLines = symbolLines
        self.memoryLines = memoryLines
        self.segmentLines = segmentLines
        self.reuseCandidateLines = reuseCandidateLines
        self.evidenceCards = evidenceCards
        self.intent = intent
        self.retrievalConfidence = retrievalConfidence
    }

    public static let empty = RAGRetrievalResult(
        projectOverviewLines: [],
        symbolLines: [],
        memoryLines: [],
        segmentLines: [],
        reuseCandidateLines: [],
        evidenceCards: [],
        intent: .other,
        retrievalConfidence: 0
    )
}

public struct MemorySimilarityResult: Sendable {
    public let entry: MemoryEntry
    public let similarityScore: Double

    public init(entry: MemoryEntry, similarityScore: Double) {
        self.entry = entry
        self.similarityScore = similarityScore
    }
}

/// Protocol for services that can search memories by semantic similarity.
/// NOT isolated to @MainActor to avoid blocking UI during embedding generation.
public protocol MemoryEmbeddingSearchProviding: Sendable {
    func getRelevantMemories(userInput: String, limit: Int) async throws -> [MemorySimilarityResult]
}
