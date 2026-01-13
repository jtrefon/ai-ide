import Foundation
import SQLite3

final class DatabaseAIEnrichmentManager {
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

    func markAIEnriched(resourceId: String, score: Double, summary: String?) throws {
        // Preserve heuristic scores: an AI score of 0 means "unknown" and must not clobber an existing score.
        let sql = "UPDATE resources SET ai_enriched = 1, " +
            "quality_score = CASE WHEN ? > 0 THEN ? ELSE quality_score END, " +
            "summary = ? WHERE id = ?;"
        let summaryValue: Any = summary ?? NSNull()
        try database.execute(sql: sql, parameters: [score, score, summaryValue, resourceId])
    }

    func updateQualityScore(resourceId: String, score: Double) throws {
        let sql = "UPDATE resources SET quality_score = ? WHERE id = ?;"
        try database.execute(sql: sql, parameters: [score, resourceId])
    }

    func updateQualityDetails(resourceId: String, details: String?) throws {
        let sql = "UPDATE resources SET quality_details = ? WHERE id = ?;"
        let detailsValue: Any = details ?? NSNull()
        try database.execute(sql: sql, parameters: [detailsValue, resourceId])
    }

    func getQualityScore(resourceId: String) throws -> Double? {
        let sql = "SELECT quality_score FROM resources WHERE id = ? LIMIT 1;"
        return try withPreparedStatement(sql: sql, parameters: [resourceId]) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return sqlite3_column_double(statement, 0)
        }
    }

    func getAverageQualityScore() throws -> Double {
        let sql = "SELECT AVG(quality_score) FROM resources WHERE quality_score > 0;"
        return try database.scalarDouble(sql: sql)
    }

    func getAIEnrichedSummaries(projectRoot: URL, limit: Int) throws -> [(path: String, summary: String)] {
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")

        let sql = "SELECT path, summary FROM resources WHERE ai_enriched = 1 AND path LIKE ? " +
            "AND summary IS NOT NULL AND summary != '' ORDER BY quality_score DESC LIMIT ?;"

        let parameters: [Any] = [rootPrefix + "%", limit]
        return try withPreparedStatement(sql: sql, parameters: parameters) { statement in
            var results: [(path: String, summary: String)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathPtr = sqlite3_column_text(statement, 0),
                   let summaryPtr = sqlite3_column_text(statement, 1) {
                    results.append((String(cString: pathPtr), String(cString: summaryPtr)))
                }
            }
            return results
        }
    }

    func getAIEnrichedResourceCountScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Int {
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")

        let extPredicates = allowedExtensions
            .map { _ in "LOWER(path) LIKE ?" }
            .sorted()
            .joined(separator: " OR ")

        let sql = "SELECT COUNT(*) FROM resources WHERE ai_enriched = 1 AND path LIKE ? AND (\(extPredicates));"

        var parameters: [Any] = [rootPrefix + "%"]
        parameters.append(contentsOf: allowedExtensions.sorted().map { "%.\($0)" })

        return try database.scalarInt(sql: sql, parameters: parameters)
    }

    func getAverageAIQualityScoreScoped(projectRoot: URL, allowedExtensions: Set<String>) throws -> Double {
        let rootPath = projectRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")

        let extPredicates = allowedExtensions
            .map { _ in "LOWER(path) LIKE ?" }
            .sorted()
            .joined(separator: " OR ")

        let sql = "SELECT AVG(quality_score) FROM resources WHERE ai_enriched = 1 " +
                "AND quality_score > 0 AND path LIKE ? AND (\(extPredicates));"

        var parameters: [Any] = [rootPrefix + "%"]
        parameters.append(contentsOf: allowedExtensions.sorted().map { "%.\($0)" })

        return try database.scalarDouble(sql: sql, parameters: parameters)
    }
}
