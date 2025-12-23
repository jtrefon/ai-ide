import Foundation
import SQLite3

public struct SymbolSearchResult: Sendable {
    public let symbol: Symbol
    public let filePath: String?
}

public final class QueryService {
    private let database: DatabaseManager

    public init(database: DatabaseManager) {
        self.database = database
    }

    public func searchSymbols(nameLike query: String, limit: Int = 50) throws -> [Symbol] {
        try database.searchSymbols(nameLike: query, limit: limit)
    }

    public func getMemories(tier: MemoryTier? = nil) throws -> [MemoryEntry] {
        try database.getMemories(tier: tier)
    }
}
