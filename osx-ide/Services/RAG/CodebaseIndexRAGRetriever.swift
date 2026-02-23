import Foundation

/// RAG retriever that performs context retrieval from the codebase index.
/// NOT isolated to @MainActor to avoid blocking UI during embedding generation.
/// All operations run asynchronously off the main thread.
public final class CodebaseIndexRAGRetriever: RAGRetriever, @unchecked Sendable {
    private let index: CodebaseIndexProtocol

    public init(index: CodebaseIndexProtocol) {
        self.index = index
    }

    public func retrieve(_ request: RAGRetrievalRequest) async -> RAGRetrievalResult {
        let projectOverviewLines = await retrieveProjectOverviewLines(projectRoot: request.projectRoot)
        let symbolLines = await retrieveSymbolLines(userInput: request.userInput, projectRoot: request.projectRoot)
        let memoryLines = await retrieveMemoryLines(userInput: request.userInput)

        return RAGRetrievalResult(
            projectOverviewLines: projectOverviewLines,
            symbolLines: symbolLines,
            memoryLines: memoryLines
        )
    }

    private func retrieveProjectOverviewLines(projectRoot: URL?) async -> [String] {
        guard let projectRoot else { return [] }
        guard let summaries = try? await index.getSummaries(projectRoot: projectRoot, limit: 10) else { return [] }

        return summaries
            .sorted(by: { $0.path < $1.path })
            .map { "- \(relPath($0.path, projectRoot: projectRoot)): \($0.summary)" }
    }

    private func retrieveSymbolLines(userInput: String, projectRoot: URL?) async -> [String] {
        let tokens = tokenizeForSymbolSearch(userInput)
        let queryTokens = uniqueOrderedTokens(tokens).prefix(5)

        var symbolResults: [SymbolSearchResult] = []
        for token in queryTokens {
            if let found = try? await index.searchSymbolsWithPaths(nameLike: token, limit: 10) {
                symbolResults.append(contentsOf: found)
            }
        }

        let uniqueSortedResults = deduplicateSymbolResults(symbolResults)
            .sorted(by: { lhs, rhs in
                let lhsFile = lhs.filePath ?? ""
                let rhsFile = rhs.filePath ?? ""
                if lhs.symbol.name != rhs.symbol.name { return lhs.symbol.name < rhs.symbol.name }
                if lhsFile != rhsFile { return lhsFile < rhsFile }
                if lhs.symbol.lineStart != rhs.symbol.lineStart { return lhs.symbol.lineStart < rhs.symbol.lineStart }
                return lhs.symbol.lineEnd < rhs.symbol.lineEnd
            })

        return uniqueSortedResults.prefix(25).map { result in
            let symbol = result.symbol
            if let filePath = result.filePath {
                let displayPath: String
                if let projectRoot {
                    displayPath = relPath(filePath, projectRoot: projectRoot)
                } else {
                    displayPath = filePath
                }
                return "- [\(symbol.kind.rawValue)] \(symbol.name) (\(displayPath):\(symbol.lineStart)-\(symbol.lineEnd))"
            }
            return "- [\(symbol.kind.rawValue)] \(symbol.name) (lines \(symbol.lineStart)-\(symbol.lineEnd))"
        }
    }

    private func retrieveMemoryLines(userInput: String) async -> [String] {
        if let provider = index as? MemoryEmbeddingSearchProviding,
           let embeddingMatches = try? await provider.getRelevantMemories(userInput: userInput, limit: 15),
           !embeddingMatches.isEmpty {
            return embeddingMatches.map { "- \($0.entry.content)" }
        }

        guard let longTerm = try? await index.getMemories(tier: .longTerm) else { return [] }

        return longTerm
            .map(\.content)
            .sorted()
            .prefix(15)
            .map { "- \($0)" }
    }

    private func relPath(_ absPath: String, projectRoot: URL) -> String {
        let root = projectRoot.standardizedFileURL.path
        if absPath.hasPrefix(root + "/") {
            return String(absPath.dropFirst(root.count + 1))
        }
        return absPath
    }

    private func tokenizeForSymbolSearch(_ userInput: String) -> [String] {
        userInput
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map { String($0).lowercased() }
            .filter { $0.count >= 3 }
    }

    private func deduplicateSymbolResults(_ results: [SymbolSearchResult]) -> [SymbolSearchResult] {
        var seen: Set<String> = []
        var deduplicated: [SymbolSearchResult] = []

        for result in results {
            let symbol = result.symbol
            let key = [
                symbol.kind.rawValue.lowercased(),
                symbol.name.lowercased(),
                (result.filePath ?? "").lowercased(),
                String(symbol.lineStart),
                String(symbol.lineEnd)
            ].joined(separator: "|")

            if seen.contains(key) { continue }
            seen.insert(key)
            deduplicated.append(result)
        }

        return deduplicated
    }

    private func uniqueOrderedTokens(_ tokens: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for token in tokens {
            if seen.contains(token) { continue }
            seen.insert(token)
            ordered.append(token)
        }

        return ordered
    }
}
