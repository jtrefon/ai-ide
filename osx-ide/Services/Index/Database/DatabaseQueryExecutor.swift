import Foundation
import SQLite3

final class DatabaseQueryExecutor {
    private unowned let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
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

        var results: [String] = []
        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            for (index, parameter) in parameters.enumerated() {
                try database.bindParameter(statement: statement!, index: Int32(index + 1), value: parameter)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(statement, 0) {
                    results.append(String(cString: ptr))
                }
            }
        }

        return results
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

        var paths: [String] = []
        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, q, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(statement, 0) {
                    paths.append(String(cString: pathPtr))
                }
            }
        }

        return paths
    }

    func hasResourcePath(_ absolutePath: String) throws -> Bool {
        let sql = "SELECT 1 FROM resources WHERE path = ? LIMIT 1;"
        var found = false

        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
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

    func findResourceMatches(query: String, limit: Int) throws -> [IndexedFileMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        let sql = "SELECT path, ai_enriched, quality_score FROM resources " +
                "WHERE LOWER(path) LIKE LOWER(?) ORDER BY path LIMIT ?;"

        var results: [IndexedFileMatch] = []
        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            try database.bindParameter(statement: statement!, index: 1, value: "%\(trimmed)%")
            try database.bindParameter(statement: statement!, index: 2, value: limit)

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

    func getResourceLastModified(resourceId: String) throws -> Double? {
        let sql = "SELECT last_modified FROM resources WHERE id = ? LIMIT 1;"
        var result: Double?

        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
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

    func getResourceContentHash(resourceId: String) throws -> String? {
        let sql = "SELECT content_hash FROM resources WHERE id = ? LIMIT 1;"
        var result: String?

        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
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

    func isResourceAIEnriched(resourceId: String) throws -> Bool {
        let sql = "SELECT ai_enriched FROM resources WHERE id = ? LIMIT 1;"
        var result = false

        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
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

        var results: [(path: String, snippet: String)] = []
        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
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
}
