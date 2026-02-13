import Foundation

@MainActor
public protocol RAGRetriever: Sendable {
    func retrieve(_ request: RAGRetrievalRequest) async -> RAGRetrievalResult
}
