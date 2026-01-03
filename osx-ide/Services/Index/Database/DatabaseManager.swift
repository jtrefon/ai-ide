//
//  DatabaseManager.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation
import SQLite3

public enum DatabaseError: Error {
    case openFailed
    case prepareFailed
    case stepFailed
    case bindFailed
    case executionFailed(String)
}

public class DatabaseManager: @unchecked Sendable {
    public var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.osx-ide.database", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UUID>()
    private let queueID = UUID()
    
    public init(path: String) throws {
        self.dbPath = path
        queue.setSpecific(key: queueKey, value: queueID)
        try open()
        try createTables()
    }

    public func getAIEnrichedResourceCountScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Int {
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")

        let extPredicates = allowedExtensions
            .map { _ in "LOWER(path) LIKE ?" }
            .sorted()
            .joined(separator: " OR ")

        let sql = "SELECT COUNT(*) FROM resources WHERE ai_enriched = 1 AND path LIKE ? AND (\(extPredicates));"
        
        var parameters: [Any] = [rootPrefix + "%"]
        parameters.append(contentsOf: allowedExtensions.sorted().map { "%.\($0)" })
        
        return try scalarInt(sql: sql, parameters: parameters)
    }

    public func getAverageAIQualityScoreScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Double {
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")

        let extPredicates = allowedExtensions
            .map { _ in "LOWER(path) LIKE ?" }
            .sorted()
            .joined(separator: " OR ")

        let sql = "SELECT AVG(COALESCE(quality_score, 0)) FROM resources WHERE ai_enriched = 1 AND path LIKE ? AND (\(extPredicates));"
        
        var parameters: [Any] = [rootPrefix + "%"]
        parameters.append(contentsOf: allowedExtensions.sorted().map { "%.\($0)" })
        
        return try scalarDouble(sql: sql, parameters: parameters)
    }
    
    deinit {
        close()
    }
    
    private func open() throws {
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw DatabaseError.openFailed
        }
    }
    
    private func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS resources (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            language TEXT NOT NULL,
            last_modified REAL NOT NULL,
            content_hash TEXT,
            quality_score REAL
        );
        
        CREATE VIRTUAL TABLE IF NOT EXISTS resources_fts USING fts5(
            path,
            content,
            content_id UNINDEXED
        );
        
        CREATE TABLE IF NOT EXISTS symbols (
            id TEXT PRIMARY KEY,
            resource_id TEXT NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            line_start INTEGER NOT NULL,
            line_end INTEGER NOT NULL,
            description TEXT,
            FOREIGN KEY(resource_id) REFERENCES resources(id) ON DELETE CASCADE
        );
        
        CREATE INDEX IF NOT EXISTS idx_resources_path ON resources(path);
        CREATE INDEX IF NOT EXISTS idx_symbols_resource_id ON symbols(resource_id);
        CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);
        
        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            tier TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            timestamp REAL NOT NULL,
            protection_level INTEGER NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_memories_tier ON memories(tier);
        CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category);
        """
        
        try execute(sql: sql)

        // Lightweight migration: add ai_enriched flag if missing.
        try ensureColumnExists(table: "resources", column: "ai_enriched", columnDefinition: "INTEGER NOT NULL DEFAULT 0")
        try ensureColumnExists(table: "resources", column: "summary", columnDefinition: "TEXT")
    }

    private func ensureColumnExists(table: String, column: String, columnDefinition: String) throws {
        let sql = "PRAGMA table_info(\(table));"
        var existingColumns = Set<String>()

        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(statement, 1) {
                    existingColumns.insert(String(cString: namePtr))
                }
            }
        }

        guard !existingColumns.contains(column) else { return }
        try execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(columnDefinition);")
    }
    
    // MARK: - Memory Operations
    
    public func saveMemory(_ memory: MemoryEntry) throws {
        let sql = """
        INSERT INTO memories (id, tier, content, category, timestamp, protection_level)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            tier = excluded.tier,
            content = excluded.content,
            category = excluded.category,
            timestamp = excluded.timestamp,
            protection_level = excluded.protection_level;
        """
        try execute(sql: sql, parameters: [
            memory.id,
            memory.tier.rawValue,
            memory.content,
            memory.category,
            memory.timestamp.timeIntervalSince1970,
            memory.protectionLevel
        ])
    }
    
    public func getMemories(tier: MemoryTier? = nil) throws -> [MemoryEntry] {
        var sql = "SELECT id, tier, content, category, timestamp, protection_level FROM memories"
        var parameters: [Any] = []
        if let tier = tier {
            sql += " WHERE tier = ?"
            parameters.append(tier.rawValue)
        }
        sql += " ORDER BY timestamp DESC;"
        
        var memories: [MemoryEntry] = []
        
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            
            defer { sqlite3_finalize(statement) }
            
            for (index, parameter) in parameters.enumerated() {
                try bindParameter(statement: statement!, index: Int32(index + 1), value: parameter)
            }
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let tierStr = String(cString: sqlite3_column_text(statement, 1))
                let content = String(cString: sqlite3_column_text(statement, 2))
                let category = String(cString: sqlite3_column_text(statement, 3))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let protectionLevel = Int(sqlite3_column_int(statement, 5))
                
                if let tier = MemoryTier(rawValue: tierStr) {
                    let memory = MemoryEntry(
                        id: id,
                        tier: tier,
                        content: content,
                        category: category,
                        timestamp: timestamp,
                        protectionLevel: protectionLevel
                    )
                    memories.append(memory)
                }
            }
        }
        
        return memories
    }
    
    public func deleteMemory(id: String) throws {
        let sql = "DELETE FROM memories WHERE id = ?;"
        try execute(sql: sql, parameters: [id])
    }

    public func saveSymbols(_ symbols: [Symbol]) throws {
        try syncOnQueue {
            try executeUnsafe(sql: "BEGIN TRANSACTION")
            do {
                let stmt = "INSERT INTO symbols (id, resource_id, name, kind, line_start, line_end, description) VALUES (?, ?, ?, ?, ?, ?, ?);"
                var statement: OpaquePointer?

                if sqlite3_prepare_v2(db, stmt, -1, &statement, nil) != SQLITE_OK {
                    throw DatabaseError.prepareFailed
                }

                defer { sqlite3_finalize(statement) }

                for symbol in symbols {
                    sqlite3_bind_text(statement, 1, (symbol.id as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (symbol.resourceId as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 3, (symbol.name as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 4, (symbol.kind.rawValue as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(statement, 5, Int32(symbol.lineStart))
                    sqlite3_bind_int(statement, 6, Int32(symbol.lineEnd))

                    if let description = symbol.description {
                        sqlite3_bind_text(statement, 7, (description as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statement, 7)
                    }

                    if sqlite3_step(statement) != SQLITE_DONE {
                        throw DatabaseError.stepFailed
                    }

                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                }

                try executeUnsafe(sql: "COMMIT")
            } catch {
                try? executeUnsafe(sql: "ROLLBACK")
                throw error
            }
        }
    }
    
    public func deleteSymbols(for resourceId: String) throws {
        let sql = "DELETE FROM symbols WHERE resource_id = ?;"
        try execute(sql: sql, parameters: [resourceId])
    }

    public func listResourcePaths(matching query: String?, limit: Int, offset: Int) throws -> [String] {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !(trimmed?.isEmpty ?? true)

        let sql: String
        let parameters: [Any]
        if hasQuery {
            sql = "SELECT path FROM resources WHERE LOWER(path) LIKE LOWER(?) ORDER BY path LIMIT ? OFFSET ?;"
            parameters = ["%\(trimmed!)%", limit, offset]
        } else {
            sql = "SELECT path FROM resources ORDER BY path LIMIT ? OFFSET ?;"
            parameters = [limit, offset]
        }

        var results: [String] = []
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            for (index, parameter) in parameters.enumerated() {
                try bindParameter(statement: statement!, index: Int32(index + 1), value: parameter)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(statement, 0) {
                    results.append(String(cString: ptr))
                }
            }
        }

        return results
    }

    public func hasResourcePath(_ absolutePath: String) throws -> Bool {
        let sql = "SELECT 1 FROM resources WHERE path = ? LIMIT 1;"
        var found = false

        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (absolutePath as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                found = true
            }
        }

        return found
    }

    public func findResourceMatches(query: String, limit: Int) throws -> [IndexedFileMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        let sql = "SELECT path, ai_enriched, quality_score FROM resources WHERE LOWER(path) LIKE LOWER(?) ORDER BY path LIMIT ?;"

        var results: [IndexedFileMatch] = []
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            try bindParameter(statement: statement!, index: 1, value: "%\(trimmed)%")
            try bindParameter(statement: statement!, index: 2, value: limit)

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pathPtr = sqlite3_column_text(statement, 0) else { continue }
                let path = String(cString: pathPtr)
                let ai = sqlite3_column_int(statement, 1) != 0

                let isNull = sqlite3_column_type(statement, 2) == SQLITE_NULL
                let score: Double? = isNull ? nil : sqlite3_column_double(statement, 2)

                results.append(IndexedFileMatch(path: path, aiEnriched: ai, qualityScore: score))
            }
        }

        return results
    }

    public func getResourceLastModified(resourceId: String) throws -> Double? {
        let sql = "SELECT last_modified FROM resources WHERE id = ? LIMIT 1;"
        var result: Double?

        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (resourceId as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                result = sqlite3_column_double(statement, 0)
            }
        }

        return result
    }

    public func getResourceContentHash(resourceId: String) throws -> String? {
        let sql = "SELECT content_hash FROM resources WHERE id = ? LIMIT 1;"
        var result: String?

        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (resourceId as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(statement, 0) {
                    result = String(cString: ptr)
                }
            }
        }

        return result
    }

    public func isResourceAIEnriched(resourceId: String) throws -> Bool {
        let sql = "SELECT ai_enriched FROM resources WHERE id = ? LIMIT 1;"
        var result = false

        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (resourceId as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                result = sqlite3_column_int(statement, 0) != 0
            }
        }

        return result
    }

    public func searchSymbols(nameLike query: String, limit: Int = 50) throws -> [Symbol] {
        let sql = "SELECT id, resource_id, name, kind, line_start, line_end, description FROM symbols WHERE name LIKE ? ORDER BY name LIMIT ?;"

        var results: [Symbol] = []
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, "%\(query)%", -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let resourceId = String(cString: sqlite3_column_text(statement, 1))
                let name = String(cString: sqlite3_column_text(statement, 2))
                let kindRaw = String(cString: sqlite3_column_text(statement, 3))
                let lineStart = Int(sqlite3_column_int(statement, 4))
                let lineEnd = Int(sqlite3_column_int(statement, 5))
                let descriptionPtr = sqlite3_column_text(statement, 6)
                let description = descriptionPtr != nil ? String(cString: descriptionPtr!) : nil

                let kind = SymbolKind(rawValue: kindRaw) ?? .unknown
                results.append(Symbol(id: id, resourceId: resourceId, name: name, kind: kind, lineStart: lineStart, lineEnd: lineEnd, description: description))
            }
        }
        return results
    }

    public func getIndexStatsCounts() throws -> (indexedResourceCount: Int, symbolCount: Int, memoryCount: Int, longTermMemoryCount: Int) {
        let resourceCount = try scalarInt(sql: "SELECT COUNT(*) FROM resources;")
        let symbolCount = try scalarInt(sql: "SELECT COUNT(*) FROM symbols;")
        let memoryCount = try scalarInt(sql: "SELECT COUNT(*) FROM memories;")
        let longTermMemoryCount = try scalarInt(sql: "SELECT COUNT(*) FROM memories WHERE tier = 'long';")
        return (resourceCount, symbolCount, memoryCount, longTermMemoryCount)
    }

    public func getIndexedResourceCountScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Int {
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")

        let extPredicates = allowedExtensions
            .map { _ in "LOWER(path) LIKE ?" }
            .sorted()
            .joined(separator: " OR ")

        let sql = "SELECT COUNT(*) FROM resources WHERE path LIKE ? AND (\(extPredicates));"
        
        var parameters: [Any] = [rootPrefix + "%"]
        parameters.append(contentsOf: allowedExtensions.sorted().map { "%.\($0)" })
        
        return try scalarInt(sql: sql, parameters: parameters)
    }

    public func updateQualityScore(resourceId: String, score: Double) throws {
        let sql = "UPDATE resources SET quality_score = ? WHERE id = ?;"
        try execute(sql: sql, parameters: [score, resourceId])
    }

    public func markAIEnriched(resourceId: String, score: Double, summary: String?) throws {
        let sql = "UPDATE resources SET ai_enriched = 1, quality_score = ?, summary = ? WHERE id = ?;"
        try execute(sql: sql, parameters: [score, summary as Any, resourceId])
    }

    public func getSymbolKindCounts() throws -> [String: Int] {
        let sql = "SELECT kind, COUNT(*) FROM symbols GROUP BY kind;"
        var results: [String: Int] = [:]
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                let kind = String(cString: sqlite3_column_text(statement, 0))
                let count = Int(sqlite3_column_int(statement, 1))
                results[kind] = count
            }
        }
        return results
    }

    public func getAverageQualityScore() throws -> Double {
        let sql = "SELECT AVG(COALESCE(quality_score, 0)) FROM resources;"
        return try scalarDouble(sql: sql)
    }

    public func getAIEnrichedSummaries(projectRoot: URL, limit: Int = 20) throws -> [(path: String, summary: String)] {
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")
        
        let sql = "SELECT path, summary FROM resources WHERE ai_enriched = 1 AND path LIKE ? AND summary IS NOT NULL AND summary != '' ORDER BY quality_score DESC LIMIT ?;"
        
        var results: [(path: String, summary: String)] = []
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, rootPrefix + "%", -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(statement, 0),
                   let summaryPtr = sqlite3_column_text(statement, 1) {
                    results.append((String(cString: pathPtr), String(cString: summaryPtr)))
                }
            }
        }
        return results
    }

    public func searchFTS(query: String, limit: Int) throws -> [(path: String, snippet: String)] {
        let sql = """
        SELECT path, snippet(resources_fts, 1, '', '', '...', 64) as match_snippet 
        FROM resources_fts 
        WHERE resources_fts MATCH ? 
        ORDER BY rank 
        LIMIT ?;
        """
        
        var results: [(path: String, snippet: String)] = []
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, query, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(statement, 0),
                   let snippetPtr = sqlite3_column_text(statement, 1) {
                    results.append((String(cString: pathPtr), String(cString: snippetPtr)))
                }
            }
        }
        return results
    }

    public func execute(sql: String, parameters: [Any]) throws {
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }
            
            for (index, parameter) in parameters.enumerated() {
                try bindParameter(statement: statement!, index: Int32(index + 1), value: parameter)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
            }
        }
    }
    
    private func bindParameter(statement: OpaquePointer, index: Int32, value: Any) throws {
        if let string = value as? String {
            sqlite3_bind_text(statement, index, (string as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else if let int = value as? Int {
            sqlite3_bind_int(statement, index, Int32(int))
        } else if let double = value as? Double {
            sqlite3_bind_double(statement, index, double)
        } else if let int32 = value as? Int32 {
            sqlite3_bind_int(statement, index, int32)
        } else if let int64 = value as? Int64 {
            sqlite3_bind_int64(statement, index, int64)
        } else if value is NSNull {
            sqlite3_bind_null(statement, index)
        } else if let opt = value as? Optional<Any>, opt == nil {
            sqlite3_bind_null(statement, index)
        } else {
            // Fallback for other types
            let stringValue = "\(value)"
            sqlite3_bind_text(statement, index, (stringValue as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
    
    public func execute(sql: String) throws {
        try syncOnQueue {
            try executeUnsafe(sql: sql)
        }
    }

    public func transaction(_ block: () throws -> Void) throws {
        try syncOnQueue {
            try executeUnsafe(sql: "BEGIN TRANSACTION")
            do {
                try block()
                try executeUnsafe(sql: "COMMIT")
            } catch {
                try? executeUnsafe(sql: "ROLLBACK")
                throw error
            }
        }
    }

    private func scalarInt(sql: String, parameters: [Any] = []) throws -> Int {
        var result: Int = 0
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            for (index, parameter) in parameters.enumerated() {
                try bindParameter(statement: statement!, index: Int32(index + 1), value: parameter)
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.stepFailed
            }
            result = Int(sqlite3_column_int(statement, 0))
        }
        return result
    }

    private func scalarDouble(sql: String, parameters: [Any] = []) throws -> Double {
        var result: Double = 0
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            for (index, parameter) in parameters.enumerated() {
                try bindParameter(statement: statement!, index: Int32(index + 1), value: parameter)
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.stepFailed
            }
            result = sqlite3_column_double(statement, 0)
        }
        return result
    }

    internal func syncOnQueue<T>(_ work: () throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueID {
            return try work()
        }
        return try queue.sync {
            try work()
        }
    }

    private func executeUnsafe(sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw DatabaseError.executionFailed(message)
        }
    }
}
