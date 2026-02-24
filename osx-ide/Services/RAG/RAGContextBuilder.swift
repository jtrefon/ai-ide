import Foundation

public enum RAGContextBuilder {
    public static func buildContext(
        userInput: String,
        explicitContext: String?,
        retriever: (any RAGRetriever)?,
        projectRoot: URL?,
        eventBus: (any EventBusProtocol)? = nil
    ) async -> String? {
        var parts: [String] = []

        if let explicitContext {
            let trimmed = explicitContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }

        guard let retriever else {
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        // Publish retrieval started event
        eventBus?.publish(RAGRetrievalStartedEvent(userInputPreview: userInput))

        // Wrap RAG retrieval with power management to prevent sleep during long operations
        let retrieval = await AgentActivityCoordinator.shared.withActivity(type: .ragRetrieval) {
            await retriever.retrieve(RAGRetrievalRequest(userInput: userInput, projectRoot: projectRoot))
        }
        let ragBlock = formatRAGBlock(retrieval)

        // Publish retrieval completed event
        eventBus?.publish(RAGRetrievalCompletedEvent(
            symbolCount: retrieval.symbolLines.count,
            overviewCount: retrieval.projectOverviewLines.count,
            memoryCount: retrieval.memoryLines.count,
            contextCharCount: ragBlock?.count ?? 0
        ))

        // DIAGNOSTIC: Log RAG context size
        if let ragBlock {
            print("[RAGContext] Added \(ragBlock.count) chars from RAG: symbols=\(retrieval.symbolLines.count), overview=\(retrieval.projectOverviewLines.count), memory=\(retrieval.memoryLines.count)")
            parts.append(ragBlock)
        }

        let result = parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        if let result {
            print("[RAGContext] Total context size: \(result.count) chars")
        }
        return result
    }

    private static func formatRAGBlock(_ retrieval: RAGRetrievalResult) -> String? {
        var sections: [String] = []

        if !retrieval.projectOverviewLines.isEmpty {
            sections.append("PROJECT OVERVIEW (Key Files):\n" + retrieval.projectOverviewLines.joined(separator: "\n"))
        }

        if !retrieval.symbolLines.isEmpty {
            sections.append("CODEBASE INDEX (matching symbols):\n" + retrieval.symbolLines.joined(separator: "\n"))
        }

        if !retrieval.memoryLines.isEmpty {
            sections.append("PROJECT MEMORY (long-term rules):\n" + retrieval.memoryLines.joined(separator: "\n"))
        }

        guard !sections.isEmpty else { return nil }
        return "RAG CONTEXT:\n" + sections.joined(separator: "\n\n")
    }
}
