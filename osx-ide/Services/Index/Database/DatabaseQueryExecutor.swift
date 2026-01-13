import Foundation
import SQLite3

final class DatabaseQueryExecutor {
    private unowned let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    private func withPreparedStatement<T>(
        sql: String,
        work: (OpaquePointer) throws -> T
    ) throws -> T {
        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            guard let statement else {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            return try work(statement)
        }
    }

    private func withPreparedStatement<T>(
        sql: String,
        parameters: [Any],
        work: (OpaquePointer) throws -> T
    ) throws -> T {
        try withPreparedStatement(sql: sql) { statement in
            for (index, parameter) in parameters.enumerated() {
                try database.bindParameter(statement: statement, index: Int32(index + 1), value: parameter)
            }
            return try work(statement)
        }
    }

    func listResourcePaths(matching query: String?, limit: Int, offset: Int) throws -> [String] {
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

        return try withPreparedStatement(sql: sql, parameters: parameters) { statement in
            var results: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(statement, 0) {
                    results.append(String(cString: ptr))
                }
            }
            return results
        }
    }

    func candidatePathsForFTS(query: String, limit: Int) throws -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return [] }

        let sql = """
        SELECT path
        FROM resources_fts
        WHERE resources_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """

        return try withPreparedStatement(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, q, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var paths: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(statement, 0) {
                    paths.append(String(cString: pathPtr))
                }
            }
            return paths
        }
    }

    func hasResourcePath(_ absolutePath: String) throws -> Bool {
        let sql = "SELECT 1 FROM resources WHERE path = ? LIMIT 1;"
        return try withPreparedStatement(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, (absolutePath as NSString).utf8String, -1, nil)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    func findResourceMatches(query: String, limit: Int) throws -> [IndexedFileMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        let sql = "SELECT path, ai_enriched, quality_score FROM resources " +
                "WHERE LOWER(path) LIKE LOWER(?) ORDER BY path LIMIT ?;"

        let parameters: [Any] = ["%\(trimmed)%", limit]
        return try withPreparedStatement(sql: sql, parameters: parameters) { statement in
            var results: [IndexedFileMatch] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pathPtr = sqlite3_column_text(statement, 0) else { continue }
                let path = String(cString: pathPtr)
                let ai = sqlite3_column_int(statement, 1) != 0

                let isNull = sqlite3_column_type(statement, 2) == SQLITE_NULL
                let score: Double? = isNull ? nil : sqlite3_column_double(statement, 2)

                results.append(IndexedFileMatch(path: path, aiEnriched: ai, qualityScore: score))
            }
            return results
        }
    }

    func getResourceLastModified(resourceId: String) throws -> Double? {
        let sql = "SELECT last_modified FROM resources WHERE id = ? LIMIT 1;"
        return try withPreparedStatement(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, (resourceId as NSString).utf8String, -1, nil)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return sqlite3_column_double(statement, 0)
        }
    }

    func getResourceContentHash(resourceId: String) throws -> String? {
        let sql = "SELECT content_hash FROM resources WHERE id = ? LIMIT 1;"
        return try withPreparedStatement(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, (resourceId as NSString).utf8String, -1, nil)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            guard let ptr = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: ptr)
        }
    }

    func isResourceAIEnriched(resourceId: String) throws -> Bool {
        let sql = "SELECT ai_enriched FROM resources WHERE id = ? LIMIT 1;"
        return try withPreparedStatement(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, (resourceId as NSString).utf8String, -1, nil)
            guard sqlite3_step(statement) == SQLITE_ROW else { return false }
            return sqlite3_column_int(statement, 0) != 0
        }
    }

    func getIndexStatsCounts() throws -> (
            indexedResourceCount: Int, 
            symbolCount: Int, 
            memoryCount: Int, 
            longTermMemoryCount: Int
        ) {
        let resourceCount = try database.scalarInt(sql: "SELECT COUNT(*) FROM resources;")
        let symbolCount = try database.scalarInt(sql: "SELECT COUNT(*) FROM symbols;")
        let memoryCount = try database.scalarInt(sql: "SELECT COUNT(*) FROM memories;")
        let longTermMemoryCount = try database.scalarInt(sql: "SELECT COUNT(*) FROM memories WHERE tier = 'long';")
        return (resourceCount, symbolCount, memoryCount, longTermMemoryCount)
    }

    func searchFTS(query: String, limit: Int) throws -> [(path: String, snippet: String)] {
        let sql = """
        SELECT path, snippet(resources_fts, 1, '', '', '...', 64) as match_snippet
        FROM resources_fts
        WHERE resources_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """

        return try withPreparedStatement(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, query, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var results: [(path: String, snippet: String)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(statement, 0),
                   let snippetPtr = sqlite3_column_text(statement, 1) {
                    results.append((String(cString: pathPtr), String(cString: snippetPtr)))
                }
            }
            return results
        }
    }
}
