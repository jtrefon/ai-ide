import Foundation

/// RAG retriever that performs context retrieval from the codebase index.
/// NOT isolated to @MainActor to avoid blocking UI during embedding generation.
/// All operations run asynchronously off the main thread.
public final class CodebaseIndexRAGRetriever: RAGRetriever, @unchecked Sendable {
    private let index: CodebaseIndexProtocol
    private let intentClassifier: RetrievalIntentClassifier
    private let ranker: RAGEvidenceFusionRanker

    public init(index: CodebaseIndexProtocol) {
        self.index = index
        self.intentClassifier = RetrievalIntentClassifier()
        self.ranker = RAGEvidenceFusionRanker()
    }

    public func retrieve(_ request: RAGRetrievalRequest) async -> RAGRetrievalResult {
        let intent = intentClassifier.classify(userInput: request.userInput)

        let overviewCandidates = await retrieveProjectOverviewCandidates(projectRoot: request.projectRoot)
        let symbolCandidates = await retrieveSymbolCandidates(userInput: request.userInput, projectRoot: request.projectRoot)
        let memoryCandidates = await retrieveMemoryCandidates(userInput: request.userInput)
        let segmentCandidates = await retrieveSegmentCandidates(userInput: request.userInput)

        let ranked = ranker.rank(
            candidates: overviewCandidates + symbolCandidates + memoryCandidates + segmentCandidates,
            userInput: request.userInput,
            intent: intent
        )
        let evidenceCards = Array(ranked.prefix(24))

        let projectOverviewLines = lines(for: .summary, from: evidenceCards)
        let symbolLines = lines(for: .symbol, from: evidenceCards)
        let memoryLines = lines(for: .memory, from: evidenceCards)
        let segmentLines = lines(for: .segment, from: evidenceCards)
        let reuseCandidateLines = reuseCandidateLines(from: evidenceCards)
        let retrievalConfidence = confidence(from: evidenceCards)

        return RAGRetrievalResult(
            projectOverviewLines: projectOverviewLines,
            symbolLines: symbolLines,
            memoryLines: memoryLines,
            segmentLines: segmentLines,
            reuseCandidateLines: reuseCandidateLines,
            evidenceCards: evidenceCards,
            intent: intent,
            retrievalConfidence: retrievalConfidence
        )
    }

    private func retrieveProjectOverviewCandidates(projectRoot: URL?) async -> [RAGEvidenceCandidate] {
        guard let projectRoot else { return [] }
        guard let summaries = try? await index.getSummaries(projectRoot: projectRoot, limit: 10) else { return [] }

        return summaries
            .sorted(by: { $0.path < $1.path })
            .map {
                let relativePath = relPath($0.path, projectRoot: projectRoot)
                let preview = "- \(relativePath): \($0.summary)"
                return RAGEvidenceCandidate(
                    id: "summary|\(relativePath)",
                    type: .summary,
                    filePath: relativePath,
                    lineStart: nil,
                    lineEnd: nil,
                    preview: preview,
                    searchableText: "\(relativePath) \($0.summary)",
                    qualityScore: inferredQualityScore(from: $0.summary),
                    freshness: 0.85
                )
            }
    }

    private func retrieveSymbolCandidates(userInput: String, projectRoot: URL?) async -> [RAGEvidenceCandidate] {
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
            let symbolName = "[\(symbol.kind.rawValue)] \(symbol.name)"
            if let filePath = result.filePath {
                let displayPath: String
                if let projectRoot {
                    displayPath = relPath(filePath, projectRoot: projectRoot)
                } else {
                    displayPath = filePath
                }
                return RAGEvidenceCandidate(
                    id: "symbol|\(symbol.kind.rawValue)|\(symbol.name)|\(displayPath)|\(symbol.lineStart)|\(symbol.lineEnd)",
                    type: .symbol,
                    filePath: displayPath,
                    lineStart: symbol.lineStart,
                    lineEnd: symbol.lineEnd,
                    preview: "- \(symbolName) (\(displayPath):\(symbol.lineStart)-\(symbol.lineEnd))",
                    searchableText: "\(symbol.name) \(displayPath) \(symbol.kind.rawValue)",
                    qualityScore: nil,
                    freshness: 0.8
                )
            }
            return RAGEvidenceCandidate(
                id: "symbol|\(symbol.kind.rawValue)|\(symbol.name)|\(symbol.lineStart)|\(symbol.lineEnd)",
                type: .symbol,
                filePath: nil,
                lineStart: symbol.lineStart,
                lineEnd: symbol.lineEnd,
                preview: "- \(symbolName) (lines \(symbol.lineStart)-\(symbol.lineEnd))",
                searchableText: "\(symbol.name) \(symbol.kind.rawValue)",
                qualityScore: nil,
                freshness: 0.8
            )
        }
    }

    private func retrieveMemoryCandidates(userInput: String) async -> [RAGEvidenceCandidate] {
        if let provider = index as? MemoryEmbeddingSearchProviding,
           let embeddingMatches = try? await provider.getRelevantMemories(userInput: userInput, limit: 15),
           !embeddingMatches.isEmpty {
            return embeddingMatches.enumerated().map { offset, match in
                let normalizedSimilarity = max(0, min(1, match.similarityScore))
                return RAGEvidenceCandidate(
                    id: "memory|semantic|\(match.entry.id)|\(offset)",
                    type: .memory,
                    filePath: nil,
                    lineStart: nil,
                    lineEnd: nil,
                    preview: "- \(match.entry.content)",
                    searchableText: match.entry.content,
                    qualityScore: nil,
                    freshness: 0.7 + (normalizedSimilarity * 0.3)
                )
            }
        }

        guard let longTerm = try? await index.getMemories(tier: .longTerm) else { return [] }

        return longTerm
            .sorted(by: { $0.content < $1.content })
            .prefix(15)
            .enumerated()
            .map { offset, entry in
                RAGEvidenceCandidate(
                    id: "memory|long_term|\(offset)",
                    type: .memory,
                    filePath: nil,
                    lineStart: nil,
                    lineEnd: nil,
                    preview: "- \(entry.content)",
                    searchableText: entry.content,
                    qualityScore: nil,
                    freshness: 0.65
                )
            }
    }

    private func retrieveSegmentCandidates(userInput: String) async -> [RAGEvidenceCandidate] {
        if let semanticProvider = index as? CodeChunkEmbeddingSearchProviding,
           let semanticMatches = try? await semanticProvider.getRelevantCodeChunks(userInput: userInput, limit: 12),
           !semanticMatches.isEmpty {
            return semanticMatches.map { match in
                RAGEvidenceCandidate(
                    id: "segment|semantic|\(match.filePath)|\(match.lineStart)|\(match.lineEnd)",
                    type: .segment,
                    filePath: match.filePath,
                    lineStart: match.lineStart,
                    lineEnd: match.lineEnd,
                    preview: "- [segment] \(match.filePath):\(match.lineStart)-\(match.lineEnd): \(match.snippet)",
                    searchableText: "\(match.filePath) \(match.snippet)",
                    qualityScore: inferredQualityScore(from: match.snippet),
                    freshness: 0.75 + max(0, min(0.2, match.similarityScore * 0.2))
                )
            }
        }

        let queryTokens = uniqueOrderedTokens(tokenizeForSymbolSearch(userInput)).prefix(3)
        guard !queryTokens.isEmpty else { return [] }

        var segments: [RAGEvidenceCandidate] = []
        for token in queryTokens {
            guard let matches = try? await index.searchIndexedText(pattern: token, limit: 8) else { continue }
            for raw in matches {
                if let candidate = makeSegmentCandidate(rawLine: raw, token: token) {
                    segments.append(candidate)
                }
            }
        }

        var seen: Set<String> = []
        var deduplicated: [RAGEvidenceCandidate] = []
        for segment in segments {
            if seen.contains(segment.id) { continue }
            seen.insert(segment.id)
            deduplicated.append(segment)
        }
        return Array(deduplicated.prefix(20))
    }

    private func makeSegmentCandidate(rawLine: String, token: String) -> RAGEvidenceCandidate? {
        let components = rawLine.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard components.count >= 3 else { return nil }

        let filePath = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lineText = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = String(components[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lineStart = Int(lineText)

        return RAGEvidenceCandidate(
            id: "segment|\(filePath)|\(lineText)|\(snippet.prefix(80))",
            type: .segment,
            filePath: filePath,
            lineStart: lineStart,
            lineEnd: lineStart,
            preview: "- [segment] \(filePath):\(lineText): \(snippet)",
            searchableText: "\(token) \(filePath) \(snippet)",
            qualityScore: inferredQualityScore(from: snippet),
            freshness: 0.75
        )
    }

    private func lines(for type: EvidenceType, from cards: [EvidenceCard]) -> [String] {
        cards
            .filter { $0.type == type }
            .map(\.preview)
    }

    private func reuseCandidateLines(from cards: [EvidenceCard]) -> [String] {
        cards
            .filter { card in
                card.type == .summary || card.type == .symbol || card.type == .segment
            }
            .prefix(6)
            .map { card in
                var location = card.filePath ?? "(project memory)"
                if let lineStart = card.lineStart {
                    location += ":\(lineStart)"
                }
                return "- Reuse candidate: \(location) | \(card.whySelected)"
            }
    }

    private func confidence(from cards: [EvidenceCard]) -> Double {
        guard !cards.isEmpty else { return 0 }
        let total = cards.reduce(0.0) { partialResult, card in
            partialResult + card.confidence
        }
        return total / Double(cards.count)
    }

    private func inferredQualityScore(from text: String) -> Double? {
        let normalized = text.lowercased()
        if normalized.contains("critical") || normalized.contains("warning") || normalized.contains("todo") {
            return 30
        }
        if normalized.contains("deprecated") || normalized.contains("legacy") {
            return 45
        }
        return nil
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
