import Foundation

extension CodebaseIndex {
    public func searchSymbols(nameLike query: String, limit: Int = 50) async throws -> [Symbol] {
        try await queryService.searchSymbols(nameLike: query, limit: limit)
    }

    public func searchSymbolsWithPaths(nameLike query: String, limit: Int = 50) async throws -> [SymbolSearchResult] {
        try await queryService.searchSymbolsWithPaths(nameLike: query, limit: limit)
    }

    public func getSummaries(projectRoot: URL, limit: Int = 20) async throws -> [(path: String, summary: String)] {
        try await database.getAIEnrichedSummaries(projectRoot: projectRoot, limit: limit)
    }

    public func getMemories(tier: MemoryTier? = nil) async throws -> [MemoryEntry] {
        try await queryService.getMemories(tier: tier)
    }
}
