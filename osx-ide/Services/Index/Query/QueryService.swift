import Foundation
import SQLite3

public struct SymbolSearchResult: Sendable {
    public let symbol: Symbol
    public let filePath: String?
}

public struct QueryService: Sendable {
    private let database: DatabaseStore

    public init(database: DatabaseStore) {
        self.database = database
    }

    public func searchSymbols(nameLike query: String, limit: Int = 50) async throws -> [Symbol] {
        try await database.searchSymbols(nameLike: query, limit: limit)
    }

    public func searchSymbolsWithPaths(nameLike query: String, limit: Int = 50) async throws -> [SymbolSearchResult] {
        try await database.searchSymbolsWithPaths(nameLike: query, limit: limit)
    }

    public func getMemories(tier: MemoryTier? = nil) async throws -> [MemoryEntry] {
        try await database.getMemories(tier: tier)
    }

    public func searchSimilarMemories(
        modelId: String,
        queryVector: [Float],
        limit: Int,
        tier: MemoryTier?
    ) async throws -> [MemorySimilarityResult] {
        try await database.searchSimilarMemories(
            modelId: modelId,
            queryVector: queryVector,
            limit: limit,
            tier: tier
        )
    }
}
