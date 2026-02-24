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
    public let contextCharCount: Int
    
    public init(symbolCount: Int, overviewCount: Int, memoryCount: Int, contextCharCount: Int) {
        self.symbolCount = symbolCount
        self.overviewCount = overviewCount
        self.memoryCount = memoryCount
        self.contextCharCount = contextCharCount
    }
}
