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

public class DatabaseManager {
    var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.osx-ide.database", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UUID>()
    private let queueID = UUID()

    private lazy var schemaManager = DatabaseSchemaManager(database: self)
    private lazy var memoryManager = DatabaseMemoryManager(database: self)
    private lazy var symbolManager = DatabaseSymbolManager(database: self)
    private lazy var queryExecutor = DatabaseQueryExecutor(database: self)
    private lazy var aiEnrichmentManager = DatabaseAIEnrichmentManager(database: self)
    
    public init(path: String) throws {
        self.dbPath = path
        queue.setSpecific(key: queueKey, value: queueID)
        try open()
        try createTables()
    }

    public func getAIEnrichedResourceCountScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Int {
        try aiEnrichmentManager.getAIEnrichedResourceCountScoped(
                    projectRoot: projectRoot, 
                    allowedExtensions: allowedExtensions
                )
    }

    public func getAverageAIQualityScoreScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Double {
        try aiEnrichmentManager.getAverageAIQualityScoreScoped(
                    projectRoot: projectRoot, 
                    allowedExtensions: allowedExtensions
                )
    }
    
    deinit {
        close()
    }

    public func shutdown() {
        queue.sync {
            close()
        }
    }
    
    private func open() throws {
        if sqlite3_open_v2(
                    dbPath, 
                    &db, 
                    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, 
                    nil
                ) != SQLITE_OK {
            throw DatabaseError.openFailed
        }

        // Performance + integrity pragmas.
        // WAL significantly improves concurrent read/write behavior for an interactive IDE.
        // foreign_keys ensures ON DELETE CASCADE works for symbols/resources.
        try execute(sql: "PRAGMA journal_mode = WAL;")
        try execute(sql: "PRAGMA synchronous = NORMAL;")
        try execute(sql: "PRAGMA foreign_keys = ON;")
    }
    
    private func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    private func createTables() throws {
        try schemaManager.createTables()
    }
    
    // MARK: - Memory Operations

    public func saveMemory(_ memory: MemoryEntry) throws {
        try memoryManager.saveMemory(memory)
    }

    public func getMemories(tier: MemoryTier? = nil) throws -> [MemoryEntry] {
        try memoryManager.getMemories(tier: tier)
    }

    public func deleteMemory(id: String) throws {
        try memoryManager.deleteMemory(id: id)
    }

    public func saveSymbols(_ symbols: [Symbol]) throws {
        try symbolManager.saveSymbols(symbols)
    }
    
    public func deleteSymbols(for resourceId: String) throws {
        try symbolManager.deleteSymbols(for: resourceId)
    }

    public func listResourcePaths(matching query: String?, limit: Int, offset: Int) throws -> [String] {
        try queryExecutor.listResourcePaths(matching: query, limit: limit, offset: offset)
    }

    public func searchSymbolsWithPaths(nameLike query: String, limit: Int = 50) throws -> [SymbolSearchResult] {
        try symbolManager.searchSymbolsWithPaths(nameLike: query, limit: limit)
    }

    public func candidatePathsForFTS(query: String, limit: Int) throws -> [String] {
        try queryExecutor.candidatePathsForFTS(query: query, limit: limit)
    }

    public func hasResourcePath(_ absolutePath: String) throws -> Bool {
        try queryExecutor.hasResourcePath(absolutePath)
    }

    public func findResourceMatches(query: String, limit: Int) throws -> [IndexedFileMatch] {
        try queryExecutor.findResourceMatches(query: query, limit: limit)
    }

    public func getResourceLastModified(resourceId: String) throws -> Double? {
        try queryExecutor.getResourceLastModified(resourceId: resourceId)
    }

    public func getResourceContentHash(resourceId: String) throws -> String? {
        try queryExecutor.getResourceContentHash(resourceId: resourceId)
    }

    public func isResourceAIEnriched(resourceId: String) throws -> Bool {
        try queryExecutor.isResourceAIEnriched(resourceId: resourceId)
    }

    public func searchSymbols(nameLike query: String, limit: Int = 50) throws -> [Symbol] {
        try symbolManager.searchSymbols(nameLike: query, limit: limit)
    }

    public func getIndexStatsCounts() throws -> (
            indexedResourceCount: Int, 
            symbolCount: Int, 
            memoryCount: Int, 
            longTermMemoryCount: Int
        ) {
        try queryExecutor.getIndexStatsCounts()
    }

    public func getIndexedResourceCountScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Int {
        let rootPrefix = DatabaseScopedPathQueryBuilder.rootPrefix(projectRoot: projectRoot)
        let extPredicates = DatabaseScopedPathQueryBuilder.fileExtensionPredicates(allowedExtensions: allowedExtensions)

        let sql = "SELECT COUNT(*) FROM resources WHERE path LIKE ? AND (\(extPredicates));"

        var parameters: [Any] = [rootPrefix + "%"]
        parameters.append(contentsOf: DatabaseScopedPathQueryBuilder.fileExtensionParameters(allowedExtensions: allowedExtensions))

        return try scalarInt(sql: sql, parameters: parameters)
    }

    public func updateQualityScore(resourceId: String, score: Double) throws {
        try aiEnrichmentManager.updateQualityScore(resourceId: resourceId, score: score)
    }

    public func updateQualityDetails(resourceId: String, details: String?) throws {
        try aiEnrichmentManager.updateQualityDetails(resourceId: resourceId, details: details)
    }

    public func getQualityScore(resourceId: String) throws -> Double? {
        try aiEnrichmentManager.getQualityScore(resourceId: resourceId)
    }

    public func markAIEnriched(resourceId: String, score: Double, summary: String?) throws {
        try aiEnrichmentManager.markAIEnriched(resourceId: resourceId, score: score, summary: summary)
    }

    public func getSymbolKindCounts() throws -> [String: Int] {
        try symbolManager.getSymbolKindCounts()
    }

    public func getAverageQualityScore() throws -> Double {
        try aiEnrichmentManager.getAverageQualityScore()
    }

    public func getAIEnrichedSummaries(projectRoot: URL, limit: Int = 20) throws -> [(path: String, summary: String)] {
        try aiEnrichmentManager.getAIEnrichedSummaries(projectRoot: projectRoot, limit: limit)
    }

    public func searchFTS(query: String, limit: Int) throws -> [(path: String, snippet: String)] {
        try queryExecutor.searchFTS(query: query, limit: limit)
    }

    internal func withPreparedStatement<T>(
        sql: String,
        parameters: [Any] = [],
        work: (OpaquePointer) throws -> T
    ) throws -> T {
        try syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            guard let statement else {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            for (index, parameter) in parameters.enumerated() {
                try bindParameter(statement: statement, index: Int32(index + 1), value: parameter)
            }

            return try work(statement)
        }
    }

    public func execute(sql: String, parameters: [Any]) throws {
        _ = try withPreparedStatement(sql: sql, parameters: parameters) { statement in
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
            }
        }
    }
    
    func bindParameter(statement: OpaquePointer, index: Int32, value: Any) throws {
        if let string = value as? String {
            sqlite3_bind_text(
                    statement, 
                    index, 
                    (string as NSString).utf8String, 
                    -1, 
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
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
        } else {
            // Fallback for other types
            let stringValue = "\(value)"
            sqlite3_bind_text(
                    statement, 
                    index, 
                    (stringValue as NSString).utf8String, 
                    -1, 
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
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

    internal func scalarInt(sql: String, parameters: [Any] = []) throws -> Int {
        try withPreparedStatement(sql: sql, parameters: parameters) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.stepFailed
            }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    internal func scalarDouble(sql: String, parameters: [Any] = []) throws -> Double {
        try withPreparedStatement(sql: sql, parameters: parameters) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.stepFailed
            }
            return sqlite3_column_double(statement, 0)
        }
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
