//
//  IndexToolsTests.swift
//  osx-ideTests
//
//  Created by Cascade on 24/12/2025.
//

import XCTest
@testable import osx_ide
import Combine

@MainActor
final class IndexToolsTests: XCTestCase {
    var codebaseIndex: MockCodebaseIndex!
    var indexFindFilesTool: IndexFindFilesTool!
    var indexListFilesTool: IndexListFilesTool!
    var indexReadFileTool: IndexReadFileTool!
    var indexSearchTextTool: IndexSearchTextTool!
    var indexSearchSymbolsTool: IndexSearchSymbolsTool!

    override func setUp() async throws {
        try await super.setUp()
        codebaseIndex = MockCodebaseIndex()
        indexFindFilesTool = IndexFindFilesTool(index: codebaseIndex)
        indexListFilesTool = IndexListFilesTool(index: codebaseIndex)
        indexReadFileTool = IndexReadFileTool(index: codebaseIndex)
        indexSearchTextTool = IndexSearchTextTool(index: codebaseIndex)
        indexSearchSymbolsTool = IndexSearchSymbolsTool(index: codebaseIndex)
    }

    func testIndexFindFilesTool_success() async throws {
        codebaseIndex.mockFindFilesResult = [
            IndexedFileMatch(path: "src/main.swift", aiEnriched: true, qualityScore: 8.5),
            IndexedFileMatch(path: "src/utils/helpers.swift", aiEnriched: false, qualityScore: nil)
        ]

        let result = try await indexFindFilesTool.execute(arguments: ToolArguments([
            "query": "main",
            "limit": 10
        ]))

        let lines = result.components(separatedBy: .newlines)
        XCTAssertTrue(lines.contains { $0.contains("src/main.swift") })
        XCTAssertTrue(lines.contains { $0.contains("src/utils/helpers.swift") })
        XCTAssertTrue(lines.contains { $0.contains("ai_enriched") })
    }

    func testIndexFindFilesTool_empty() async throws {
        codebaseIndex.mockFindFilesResult = []

        let result = try await indexFindFilesTool.execute(arguments: ToolArguments([
            "query": "nonexistent",
            "limit": 10
        ]))

        XCTAssertTrue(result.contains("No files found in index."))
    }

    func testIndexListFilesTool_success() async throws {
        codebaseIndex.mockListFilesResult = [
            "src/main.swift",
            "src/utils/helpers.swift",
            "README.md"
        ]

        let result = try await indexListFilesTool.execute(arguments: ToolArguments([
            "query": nil,
            "limit": 10,
            "offset": 0
        ]))

        let lines = result.components(separatedBy: .newlines)
        XCTAssertTrue(lines.contains { $0.contains("src/main.swift") })
        XCTAssertTrue(lines.contains { $0.contains("README.md") })
    }

    func testIndexListFilesTool_withFilter() async throws {
        codebaseIndex.mockListFilesResult = [
            "src/main.swift",
            "src/utils/helpers.swift"
        ]

        let result = try await indexListFilesTool.execute(arguments: ToolArguments([
            "query": "src",
            "limit": 10,
            "offset": 0
        ]))

        let lines = result.components(separatedBy: .newlines)
        XCTAssertTrue(lines.allSatisfy { $0.contains("src") })
    }

    func testIndexReadFileTool_success() async throws {
        codebaseIndex.mockReadFileResult = """
        1 | import Foundation
        2 |
        3 | class MyClass {
        4 |     func hello() {
        5 |         print("Hello")
        6 |     }
        7 | }
        """

        let result = try await indexReadFileTool.execute(arguments: ToolArguments([
            "path": "src/main.swift",
            "start_line": nil,
            "end_line": nil
        ]))

        let lines = result.components(separatedBy: .newlines)
        XCTAssertTrue(lines.contains { $0.contains("1 | import Foundation") })
        XCTAssertTrue(lines.contains { $0.contains("4 |     func hello()") })
    }

    func testIndexReadFileTool_withRange() async throws {
        codebaseIndex.mockReadFileResult = [
            "2 | ",
            "3 | class MyClass {",
            "4 |     func hello() {",
            "5 |         print(\"Hello\")",
            "6 |     }"
        ].joined(separator: "\n")

        let result = try await indexReadFileTool.execute(arguments: ToolArguments([
            "path": "src/main.swift",
            "start_line": 2,
            "end_line": 6
        ]))

        let lines = result.components(separatedBy: .newlines)
        XCTAssertEqual(lines.first, "2 | ")
        XCTAssertTrue(lines.contains { $0.contains("5 |         print(\"Hello\")") })
    }

    func testIndexReadFileTool_notFound() async throws {
        codebaseIndex.shouldThrowReadFileError = true

        do {
            _ = try await indexReadFileTool.execute(arguments: ToolArguments([
                "path": "nonexistent.swift",
                "start_line": nil,
                "end_line": nil
            ]))
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("File not found"))
        }
    }

    func testIndexSearchTextTool_success() async throws {
        codebaseIndex.mockSearchTextResult = [
            "src/main.swift:5:    print(\"Hello\")",
            "src/utils/helpers.swift:12:    print(\"Helpers\")"
        ]

        let result = try await indexSearchTextTool.execute(arguments: ToolArguments([
            "pattern": "print",
            "limit": 10
        ]))

        let lines = result.components(separatedBy: .newlines)
        XCTAssertTrue(lines.contains { $0.contains("src/main.swift:5:") })
        XCTAssertTrue(lines.contains { $0.contains("src/utils/helpers.swift:12:") })
    }

    func testIndexSearchTextTool_noMatches() async throws {
        codebaseIndex.mockSearchTextResult = []

        let result = try await indexSearchTextTool.execute(arguments: ToolArguments([
            "pattern": "nonexistent",
            "limit": 10
        ]))

        XCTAssertTrue(result.contains("No matches"))
    }

    func testIndexSearchSymbolsTool_success() async throws {
        codebaseIndex.mockSearchSymbolsWithPathsResult = [
            SymbolSearchResult(
                symbol: Symbol(
                    id: UUID().uuidString,
                    resourceId: "res1",
                    name: "MyClass",
                    kind: .class,
                    lineStart: 1,
                    lineEnd: 10
                ),
                filePath: "src/main.swift"
            ),
            SymbolSearchResult(
                symbol: Symbol(
                    id: UUID().uuidString,
                    resourceId: "res1",
                    name: "hello",
                    kind: .function,
                    lineStart: 4,
                    lineEnd: 6
                ),
                filePath: "src/main.swift"
            )
        ]

        let result = try await indexSearchSymbolsTool.execute(arguments: ToolArguments([
            "query": "My",
            "limit": 10
        ]))

        let lines = result.components(separatedBy: .newlines)
        XCTAssertTrue(lines.contains { $0.contains("MyClass") && $0.contains("class") })
        XCTAssertTrue(lines.contains { $0.contains("hello") && $0.contains("function") })
    }

    func testIndexSearchSymbolsTool_noMatches() async throws {
        codebaseIndex.mockSearchSymbolsWithPathsResult = []

        let result = try await indexSearchSymbolsTool.execute(arguments: ToolArguments([
            "query": "Nonexistent",
            "limit": 10
        ]))

        XCTAssertTrue(result.contains("No symbols"))
    }
}

// MARK: - Mock CodebaseIndex

@MainActor
class MockCodebaseIndex: CodebaseIndexProtocol {
    var currentEmbeddingModelIdentifier: String = "hashing_v1"
    var mockFindFilesResult: [IndexedFileMatch] = []
    var mockListFilesResult: [String] = []
    var mockReadFileResult: String = ""
    var mockSearchTextResult: [String] = []
    var mockSearchSymbolsResult: [Symbol] = []
    var mockSearchSymbolsWithPathsResult: [SymbolSearchResult] = []
    var shouldThrowReadFileError = false

    func start() {}
    func stop() {}
    func setEnabled(_ enabled: Bool) {}
    func reindexProject() {}
    func reindexProject(aiEnrichmentEnabled: Bool) {}
    func runAIEnrichment() {}
    func upgradeEmbeddingGenerator(_ generator: any MemoryEmbeddingGenerating) {}

    func getSummaries(projectRoot: URL, limit: Int) async throws -> [(path: String, summary: String)] { [] }
    func getMemories(tier: MemoryTier?) async throws -> [MemoryEntry] { [] }

    func addMemory(content: String, tier: MemoryTier, category: String) async throws -> MemoryEntry {
        MemoryEntry(
            id: UUID().uuidString,
            tier: tier,
            content: content,
            category: category,
            timestamp: Date(),
            protectionLevel: 0
        )
    }

    func getStats() async throws -> IndexStats {
        IndexStats(
            indexedResourceCount: 0,
            aiEnrichedResourceCount: 0,
            aiEnrichableProjectFileCount: 0,
            totalProjectFileCount: 0,
            symbolCount: 0,
            classCount: 0,
            structCount: 0,
            enumCount: 0,
            protocolCount: 0,
            functionCount: 0,
            variableCount: 0,
            memoryCount: 0,
            longTermMemoryCount: 0,
            databaseSizeBytes: 0,
            databasePath: "",
            isDatabaseInWorkspace: false,
            averageQualityScore: 0.0,
            averageAIQualityScore: 0.0
        )
    }

    func listIndexedFiles(matching filter: String?, limit: Int, offset: Int) async throws -> [String] { mockListFilesResult }
    func findIndexedFiles(query: String, limit: Int) async throws -> [IndexedFileMatch] { mockFindFilesResult }

    func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String {
        if shouldThrowReadFileError {
            throw NSError(domain: "MockError", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        return mockReadFileResult
    }

    func searchIndexedText(pattern: String, limit: Int) async throws -> [String] {
        return mockSearchTextResult
    }

    func searchSymbols(nameLike query: String, limit: Int) async throws -> [Symbol] { mockSearchSymbolsResult }
    func searchSymbolsWithPaths(nameLike query: String, limit: Int) async throws -> [SymbolSearchResult] { mockSearchSymbolsWithPathsResult }
}
