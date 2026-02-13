import Foundation

public enum RAGContextBuilder {
    public static func buildContext(
        userInput: String,
        explicitContext: String?,
        retriever: (any RAGRetriever)?,
        projectRoot: URL?
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

        let retrieval = await retriever.retrieve(RAGRetrievalRequest(userInput: userInput, projectRoot: projectRoot))
        let ragBlock = formatRAGBlock(retrieval)

        if let ragBlock {
            parts.append(ragBlock)
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
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
