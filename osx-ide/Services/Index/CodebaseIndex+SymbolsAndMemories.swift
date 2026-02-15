import Foundation

extension CodebaseIndex {
    public func searchSymbols(nameLike query: String, limit: Int = 50) async throws -> [Symbol] {
        try await queryService.searchSymbols(nameLike: query, limit: limit)
    }

    public func searchSymbolsWithPaths(nameLike query: String, limit: Int = 50) async throws -> [SymbolSearchResult] {
        let rawResults = try await queryService.searchSymbolsWithPaths(nameLike: query, limit: limit)
        return rawResults.compactMap { result in
            if let absolutePath = result.filePath {
                guard let relativePath = scopedRelativePath(from: absolutePath) else {
                    return nil
                }
                return SymbolSearchResult(symbol: result.symbol, filePath: relativePath)
            }

            guard let resourcePath = pathFromResourceId(result.symbol.resourceId),
                  let relativePath = scopedRelativePath(from: resourcePath) else {
                return nil
            }

            return SymbolSearchResult(symbol: result.symbol, filePath: relativePath)
        }
    }

    public func getSummaries(projectRoot: URL, limit: Int = 20) async throws -> [(path: String, summary: String)] {
        try await database.getAIEnrichedSummaries(projectRoot: projectRoot, limit: limit)
    }

    public func getMemories(tier: MemoryTier? = nil) async throws -> [MemoryEntry] {
        try await queryService.getMemories(tier: tier)
    }

    public func addMemory(content: String, tier: MemoryTier, category: String) async throws -> MemoryEntry {
        try await memoryManager.addMemory(content: content, tier: tier, category: category)
    }
}

extension CodebaseIndex: MemoryEmbeddingSearchProviding {
    public func getRelevantMemories(userInput: String, limit: Int) async throws -> [MemorySimilarityResult] {
        let safeLimit = max(1, limit)
        let queryVector = try await memoryEmbeddingGenerator.generateEmbedding(for: userInput)

        guard !queryVector.isEmpty else {
            let fallback = try await queryService.getMemories(tier: .longTerm)
            return fallback.prefix(safeLimit).map { entry in
                MemorySimilarityResult(entry: entry, similarityScore: 0)
            }
        }

        let similar = try await queryService.searchSimilarMemories(
            modelId: memoryEmbeddingGenerator.modelIdentifier,
            queryVector: queryVector,
            limit: safeLimit,
            tier: .longTerm
        )
        if !similar.isEmpty {
            return similar
        }

        let fallback = try await queryService.getMemories(tier: .longTerm)
        return fallback.prefix(safeLimit).map { entry in
            MemorySimilarityResult(entry: entry, similarityScore: 0)
        }
    }
}
