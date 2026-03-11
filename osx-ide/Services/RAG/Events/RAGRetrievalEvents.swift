import Foundation

/// Event published when RAG retrieval starts
public struct RAGRetrievalStartedEvent: Event {
    public let userInputPreview: String
    
    public init(userInputPreview: String) {
        self.userInputPreview = String(userInputPreview.prefix(50))
    }
}

/// Event published when RAG retrieval completes
public struct RAGRetrievalCompletedEvent: Event {
    public let symbolCount: Int
    public let overviewCount: Int
    public let memoryCount: Int
    public let segmentCount: Int
    public let evidenceCount: Int
    public let retrievalIntent: String
    public let retrievalConfidence: Double
    public let contextCharCount: Int
    
    public init(
        symbolCount: Int,
        overviewCount: Int,
        memoryCount: Int,
        segmentCount: Int,
        evidenceCount: Int,
        retrievalIntent: String,
        retrievalConfidence: Double,
        contextCharCount: Int
    ) {
        self.symbolCount = symbolCount
        self.overviewCount = overviewCount
        self.memoryCount = memoryCount
        self.segmentCount = segmentCount
        self.evidenceCount = evidenceCount
        self.retrievalIntent = retrievalIntent
        self.retrievalConfidence = retrievalConfidence
        self.contextCharCount = contextCharCount
    }
}

public struct RetrievalEvidencePreparedEvent: Event {
    public let evidenceCount: Int
    public let retrievalIntent: String
    public let retrievalConfidence: Double

    public init(evidenceCount: Int, retrievalIntent: String, retrievalConfidence: Double) {
        self.evidenceCount = evidenceCount
        self.retrievalIntent = retrievalIntent
        self.retrievalConfidence = retrievalConfidence
    }
}

public struct PreWritePreventionCheckStartedEvent: Event {
    public let toolName: String
    public let candidateFileCount: Int

    public init(toolName: String, candidateFileCount: Int) {
        self.toolName = toolName
        self.candidateFileCount = candidateFileCount
    }
}

public struct PreWritePreventionCheckCompletedEvent: Event {
    public let toolName: String
    public let outcome: String
    public let findingCount: Int

    public init(toolName: String, outcome: String, findingCount: Int) {
        self.toolName = toolName
        self.outcome = outcome
        self.findingCount = findingCount
    }
}

public struct DuplicateRiskDetectedEvent: Event {
    public let summary: String
    public let severity: String

    public init(summary: String, severity: String) {
        self.summary = summary
        self.severity = severity
    }
}

public struct DeadCodeRiskDetectedEvent: Event {
    public let summary: String
    public let severity: String

    public init(summary: String, severity: String) {
        self.summary = summary
        self.severity = severity
    }
}

public struct DebtPressureUpdatedEvent: Event {
    public let duplicateRiskCount: Int
    public let deadCodeRiskCount: Int
    public let guardStatus: String

    public init(duplicateRiskCount: Int, deadCodeRiskCount: Int, guardStatus: String) {
        self.duplicateRiskCount = duplicateRiskCount
        self.deadCodeRiskCount = deadCodeRiskCount
        self.guardStatus = guardStatus
    }
}
