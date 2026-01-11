import XCTest
@testable import osx_ide

final class DatabaseComponentTests: XCTestCase {

    private func makeTempDatabaseManager() throws -> DatabaseManager {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_db_component_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let dbPath = tempRoot.appendingPathComponent("test.sqlite").path
        return try DatabaseManager(path: dbPath)
    }

    func testDatabaseQueryExecutorListResourcePathsAndHasResourcePath() throws {
        let db = try makeTempDatabaseManager()

        try db.execute(sql: "INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score, quality_details, ai_enriched, summary) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);", parameters: [
            "r1",
            "/tmp/project/src/a.swift",
            "swift",
            1.0,
            "hash",
            0.0,
            NSNull(),
            0,
            NSNull()
        ])
        try db.execute(sql: "INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score, quality_details, ai_enriched, summary) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);", parameters: [
            "r2",
            "/tmp/project/src/b.tsx",
            "tsx",
            1.0,
            "hash2",
            0.0,
            NSNull(),
            0,
            NSNull()
        ])

        let executor = DatabaseQueryExecutor(database: db)

        let all = try executor.listResourcePaths(matching: nil, limit: 10, offset: 0)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains("/tmp/project/src/a.swift"))
        XCTAssertTrue(all.contains("/tmp/project/src/b.tsx"))

        let filtered = try executor.listResourcePaths(matching: "a.swift", limit: 10, offset: 0)
        XCTAssertEqual(filtered, ["/tmp/project/src/a.swift"])

        XCTAssertTrue(try executor.hasResourcePath("/tmp/project/src/a.swift"))
        XCTAssertFalse(try executor.hasResourcePath("/tmp/project/src/missing.swift"))
    }

    func testDatabaseQueryExecutorFindResourceMatchesReturnsAIAndScore() throws {
        let db = try makeTempDatabaseManager()

        try db.execute(sql: "INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score, quality_details, ai_enriched, summary) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);", parameters: [
            "r1",
            "/tmp/project/src/a.swift",
            "swift",
            1.0,
            "hash",
            0.75,
            NSNull(),
            1,
            NSNull()
        ])

        let executor = DatabaseQueryExecutor(database: db)
        let matches = try executor.findResourceMatches(query: "a.swift", limit: 10)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.path, "/tmp/project/src/a.swift")
        XCTAssertEqual(matches.first?.aiEnriched, true)
        XCTAssertEqual(matches.first?.qualityScore, 0.75)
    }

    func testDatabaseAIEnrichmentManagerMarkAndReadValues() throws {
        let db = try makeTempDatabaseManager()

        try db.execute(sql: "INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score, quality_details, ai_enriched, summary) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);", parameters: [
            "r1",
            "/tmp/project/src/a.swift",
            "swift",
            1.0,
            "hash",
            0.0,
            NSNull(),
            0,
            NSNull()
        ])

        let ai = DatabaseAIEnrichmentManager(database: db)
        try ai.markAIEnriched(resourceId: "r1", score: 0.9, summary: "Great file")

        XCTAssertEqual(try ai.getQualityScore(resourceId: "r1"), 0.9)
        XCTAssertEqual(try db.isResourceAIEnriched(resourceId: "r1"), true)

        let summaries = try ai.getAIEnrichedSummaries(projectRoot: URL(fileURLWithPath: "/tmp/project"), limit: 10)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.path, "/tmp/project/src/a.swift")
        XCTAssertEqual(summaries.first?.summary, "Great file")

        // Ensure score=0 does not clobber existing score.
        try ai.markAIEnriched(resourceId: "r1", score: 0.0, summary: "")
        XCTAssertEqual(try ai.getQualityScore(resourceId: "r1"), 0.9)
    }
}
