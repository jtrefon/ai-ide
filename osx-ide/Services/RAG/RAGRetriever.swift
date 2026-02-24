import Foundation

/// Protocol for RAG retrievers that fetch context from various sources.
/// NOT isolated to @MainActor to avoid blocking UI during retrieval operations.
public protocol RAGRetriever: Sendable {
    func retrieve(_ request: RAGRetrievalRequest) async -> RAGRetrievalResult
}
