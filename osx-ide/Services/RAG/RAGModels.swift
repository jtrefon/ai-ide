import Foundation

public struct RAGRetrievalRequest: Sendable {
    public let userInput: String
    public let projectRoot: URL?

    public init(userInput: String, projectRoot: URL?) {
        self.userInput = userInput
        self.projectRoot = projectRoot
    }
}

public struct RAGRetrievalResult: Sendable {
    public let projectOverviewLines: [String]
    public let symbolLines: [String]
    public let memoryLines: [String]

    public init(projectOverviewLines: [String], symbolLines: [String], memoryLines: [String]) {
        self.projectOverviewLines = projectOverviewLines
        self.symbolLines = symbolLines
        self.memoryLines = memoryLines
    }

    public static let empty = RAGRetrievalResult(projectOverviewLines: [], symbolLines: [], memoryLines: [])
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
