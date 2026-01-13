import Foundation

public enum DatabaseValue: Sendable {
    case string(String)
    case int(Int)
    case int64(Int64)
    case double(Double)
    case null

    var anyValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .int64(let v): return v
        case .double(let v): return v
        case .null: return NSNull()
        }
    }
}

public actor DatabaseStore {
    private let database: DatabaseManager

    public init(path: String) throws {
        self.database = try DatabaseManager(path: path)
    }

    public func shutdown() {
        database.shutdown()
    }

    public func getResourceLastModified(resourceId: String) throws -> Double? {
        try database.getResourceLastModified(resourceId: resourceId)
    }

    public func getResourceContentHash(resourceId: String) throws -> String? {
        try database.getResourceContentHash(resourceId: resourceId)
    }

    public func listResourcePaths(matching query: String?, limit: Int, offset: Int) throws -> [String] {
        try database.listResourcePaths(matching: query, limit: limit, offset: offset)
    }

    public func findResourceMatches(query: String, limit: Int) throws -> [IndexedFileMatch] {
        try database.findResourceMatches(query: query, limit: limit)
    }

    public func candidatePathsForFTS(query: String, limit: Int) throws -> [String] {
        try database.candidatePathsForFTS(query: query, limit: limit)
    }

    public func searchFTS(query: String, limit: Int) throws -> [(path: String, snippet: String)] {
        try database.searchFTS(query: query, limit: limit)
    }

    public func saveSymbols(_ symbols: [Symbol]) throws {
        try database.saveSymbols(symbols)
    }

    public func saveSymbolsBatched(_ symbols: [Symbol], batchSize: Int = 250) async throws {
        guard batchSize > 0 else {
            try database.saveSymbols(symbols)
            return
        }

        if symbols.isEmpty {
            return
        }

        var index = 0
        while index < symbols.count {
            let end = min(symbols.count, index + batchSize)
            try database.saveSymbols(Array(symbols[index..<end]))
            index = end

            if index < symbols.count {
                await Task.yield()
            }
        }
    }

    public func deleteSymbols(for resourceId: String) throws {
        try database.deleteSymbols(for: resourceId)
    }

    public func searchSymbols(nameLike query: String, limit: Int) throws -> [Symbol] {
        try database.searchSymbols(nameLike: query, limit: limit)
    }

    public func searchSymbolsWithPaths(nameLike query: String, limit: Int) throws -> [SymbolSearchResult] {
        try database.searchSymbolsWithPaths(nameLike: query, limit: limit)
    }

    public func saveMemory(_ entry: MemoryEntry) throws {
        try database.saveMemory(entry)
    }

    public func deleteMemory(id: String) throws {
        try database.deleteMemory(id: id)
    }

    public func getMemories(tier: MemoryTier? = nil) throws -> [MemoryEntry] {
        try database.getMemories(tier: tier)
    }

    public func isResourceAIEnriched(resourceId: String) throws -> Bool {
        try database.isResourceAIEnriched(resourceId: resourceId)
    }

    public func updateQualityScore(resourceId: String, score: Double) throws {
        try database.updateQualityScore(resourceId: resourceId, score: score)
    }

    public func updateQualityDetails(resourceId: String, details: String?) throws {
        try database.updateQualityDetails(resourceId: resourceId, details: details)
    }

    public func markAIEnriched(resourceId: String, score: Double, summary: String?) throws {
        try database.markAIEnriched(resourceId: resourceId, score: score, summary: summary)
    }

    public func getAIEnrichedSummaries(projectRoot: URL, limit: Int) throws -> [(path: String, summary: String)] {
        try database.getAIEnrichedSummaries(projectRoot: projectRoot, limit: limit)
    }

    public func getIndexStatsCounts() throws -> (
            indexedResourceCount: Int, 
            symbolCount: Int, 
            memoryCount: Int, 
            longTermMemoryCount: Int
        ) {
        try database.getIndexStatsCounts()
    }

    public func getIndexedResourceCountScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Int {
        try database.getIndexedResourceCountScoped(projectRoot: projectRoot, allowedExtensions: allowedExtensions)
    }

    public func getAIEnrichedResourceCountScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Int {
        try database.getAIEnrichedResourceCountScoped(projectRoot: projectRoot, allowedExtensions: allowedExtensions)
    }

    public func getAverageAIQualityScoreScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Double {
        try database.getAverageAIQualityScoreScoped(projectRoot: projectRoot, allowedExtensions: allowedExtensions)
    }

    public func getSymbolKindCounts() throws -> [String: Int] {
        try database.getSymbolKindCounts()
    }

    public func getAverageQualityScore() throws -> Double {
        try database.getAverageQualityScore()
    }

    public func execute(sql: String, parameters: [DatabaseValue]) throws {
        try database.execute(sql: sql, parameters: parameters.map { $0.anyValue })
    }

    public func upsertResourceAndFTS(
        resourceId: String,
        path: String,
        language: String,
        timestamp: Double,
        contentHash: String,
        content: String
    ) throws {
        let sql = """
        INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
        VALUES (?, ?, ?, ?, ?, 0.0)
        ON CONFLICT(id) DO UPDATE SET
            last_modified = excluded.last_modified,
            content_hash = excluded.content_hash,
            language = excluded.language;
        """

        let ftsDeleteSql = "DELETE FROM resources_fts WHERE content_id = ?;"
        let ftsInsertSql = "INSERT INTO resources_fts (path, content, content_id) VALUES (?, ?, ?);"

        try database.transaction {
            try database.execute(sql: sql, parameters: [resourceId, path, language, timestamp, contentHash])
            try database.execute(sql: ftsDeleteSql, parameters: [resourceId])
            try database.execute(sql: ftsInsertSql, parameters: [path, content, resourceId])
        }
    }

    public func deleteResource(resourceId: String) throws {
        try database.execute(sql: "DELETE FROM resources WHERE id = ?;", parameters: [resourceId])
    }
}
