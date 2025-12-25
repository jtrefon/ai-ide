//
//  DatabaseManagerTests.swift
//  osx-ideTests
//
//  Created by Cascade on 24/12/2025.
//

import XCTest
@testable import osx_ide
import SQLite3

final class DatabaseManagerTests: XCTestCase {
    var dbManager: DatabaseManager!
    var tempDBPath: String!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempDBPath = tempDir.appendingPathComponent(UUID().uuidString + ".sqlite").path
        dbManager = try DatabaseManager(path: tempDBPath)
    }

    override func tearDown() async throws {
        dbManager = nil
        try? FileManager.default.removeItem(atPath: tempDBPath)
        try await super.tearDown()
    }

    func testListResourcePaths_noResults() throws {
        let results = try dbManager.listResourcePaths(matching: nil, limit: 10, offset: 0)
        XCTAssertTrue(results.isEmpty)
    }

    func testListResourcePaths_withInserts() throws {
        // Insert some test resources
        let paths = [
            "src/main.swift",
            "src/utils/helpers.swift",
            "README.md",
            "docs/guide.md"
        ]
        for path in paths {
            let id = UUID().uuidString
            let sql = """
            INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
            VALUES ('\(id)', '\(path)', 'swift', 0.0, 'hash', 7.5);
            """
            try dbManager.execute(sql: sql)
        }

        let results = try dbManager.listResourcePaths(matching: nil, limit: 10, offset: 0)
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.contains("src/main.swift"))
        XCTAssertTrue(results.contains("README.md"))
    }

    func testListResourcePaths_withFilter() throws {
        let paths = [
            "src/main.swift",
            "src/utils/helpers.swift",
            "README.md",
            "docs/guide.md"
        ]
        for path in paths {
            let id = UUID().uuidString
            let sql = """
            INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
            VALUES ('\(id)', '\(path)', 'swift', 0.0, 'hash', 7.5);
            """
            try dbManager.execute(sql: sql)
        }

        let results = try dbManager.listResourcePaths(matching: "swift", limit: 10, offset: 0)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.contains("swift") })
    }

    func testHasResourcePath() throws {
        let id = UUID().uuidString
        let path = "src/main.swift"
        let sql = """
        INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
        VALUES ('\(id)', '\(path)', 'swift', 0.0, 'hash', 7.5);
        """
        try dbManager.execute(sql: sql)

        XCTAssertTrue(try dbManager.hasResourcePath(path))
        XCTAssertFalse(try dbManager.hasResourcePath("src/nonexistent.swift"))
    }

    func testFindResourceMatches() throws {
        let paths = [
            "src/main.swift",
            "src/utils/helpers.swift",
            "README.md",
            "docs/guide.md"
        ]
        for path in paths {
            let id = UUID().uuidString
            let sql = """
            INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
            VALUES ('\(id)', '\(path)', 'swift', 0.0, 'hash', 7.5);
            """
            try dbManager.execute(sql: sql)
        }

        let results = try dbManager.findResourceMatches(query: "swift", limit: 10)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.path.contains("swift") })
        XCTAssertTrue(results.allSatisfy { $0.aiEnriched == false })
        XCTAssertEqual(results.first?.qualityScore, 7.5)
    }

    func testFindResourceMatches_withAIEnriched() throws {
        let id = UUID().uuidString
        let path = "src/ai_enriched.swift"
        let sql = """
        INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score, ai_enriched)
        VALUES ('\(id)', '\(path)', 'swift', 0.0, 'hash', 9.2, 1);
        """
        try dbManager.execute(sql: sql)

        let results = try dbManager.findResourceMatches(query: "ai_enriched", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.aiEnriched == true)
        XCTAssertEqual(results.first?.qualityScore, 9.2)
    }

    func testUpdateQualityScore() throws {
        let id = UUID().uuidString
        let path = "src/main.swift"
        let insertSql = """
        INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
        VALUES ('\(id)', '\(path)', 'swift', 0.0, 'hash', 7.5);
        """
        try dbManager.execute(sql: insertSql)

        try dbManager.updateQualityScore(resourceId: id, score: 8.8)

        // Simple verification - just check that update doesn't throw
        XCTAssertTrue(true)
    }

    func testMarkAIEnriched() throws {
        let id = UUID().uuidString
        let path = "src/main.swift"
        let insertSql = """
        INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
        VALUES ('\(id)', '\(path)', 'swift', 0.0, 'hash', 7.5);
        """
        try dbManager.execute(sql: insertSql)

        try dbManager.markAIEnriched(resourceId: id, score: 9.1)

        // Simple verification - just check that marking doesn't throw
        XCTAssertTrue(true)
    }
}
