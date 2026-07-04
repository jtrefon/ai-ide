import XCTest
@testable import osx_ide

@MainActor
final class CodebaseIndexRAGRetrieverTests: XCTestCase {

    // MARK: - Project overview retrieval

    func testRetrieveProjectOverviewLinesFromSummaries() async {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let index = FakeRAGCodebaseIndex()
        index.stubbedSummaries = [
            (path: "\(projectRoot.path)/Sources/main.swift", summary: "Entry point"),
            (path: "\(projectRoot.path)/Sources/utils.swift", summary: "Utility helpers")
        ]

        let retriever = CodebaseIndexRAGRetriever(index: index)
        let result = await retriever.retrieve(RAGRetrievalRequest(userInput: "hello", projectRoot: projectRoot))

        XCTAssertEqual(result.projectOverviewLines.count, 2)
        XCTAssertTrue(result.projectOverviewLines[0].contains("Sources/main.swift"))
        XCTAssertTrue(result.projectOverviewLines[0].contains("Entry point"))
        XCTAssertTrue(result.projectOverviewLines[1].contains("Sources/utils.swift"))
    }

    func testRetrieveProjectOverviewLinesEmptyWhenNoProjectRoot() async {
        let index = FakeRAGCodebaseIndex()
        index.stubbedSummaries = [
            (path: "/some/file.swift", summary: "Something")
        ]

        let retriever = CodebaseIndexRAGRetriever(index: index)
        let result = await retriever.retrieve(RAGRetrievalRequest(userInput: "hello", projectRoot: nil))

        XCTAssertTrue(result.projectOverviewLines.isEmpty)
    }

    // MARK: - Symbol retrieval

    func testRetrieveSymbolLinesFromIndex() async {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let index = FakeRAGCodebaseIndex()
        index.stubbedSymbolResults = [
            SymbolSearchResult(
                symbol: Symbol(
                    id: UUID().uuidString,
                    resourceId: "res1",
                    name: "doWork",
                    kind: .function,
                    lineStart: 10,
                    lineEnd: 20,
                    description: nil
                ),
                filePath: "\(projectRoot.path)/Sources/worker.swift"
            )
        ]

        let retriever = CodebaseIndexRAGRetriever(index: index)
        let result = await retriever.retrieve(RAGRetrievalRequest(userInput: "doWork function", projectRoot: projectRoot))

        XCTAssertFalse(result.symbolLines.isEmpty)
        XCTAssertTrue(result.symbolLines[0].contains("doWork"))
        XCTAssertTrue(result.symbolLines[0].contains("function"))
    }

    func testRetrieveSymbolLinesEmptyForShortInput() async {
        let index = FakeRAGCodebaseIndex()
        index.stubbedSymbolResults = []

        let retriever = CodebaseIndexRAGRetriever(index: index)
        let result = await retriever.retrieve(RAGRetrievalRequest(userInput: "ab", projectRoot: nil))

        XCTAssertTrue(result.symbolLines.isEmpty)
    }

    func testRetrieveSymbolLinesDeduplicatesDuplicateMatches() async {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let duplicated = SymbolSearchResult(
            symbol: Symbol(
                id: UUID().uuidString,
                resourceId: "res1",
                name: "runTask",
                kind: .function,
                lineStart: 12,
                lineEnd: 19,
                description: nil
            ),
            filePath: "\(projectRoot.path)/Sources/Runner.swift"
        )

        let index = FakeRAGCodebaseIndex()
        index.stubbedSymbolResults = [duplicated, duplicated, duplicated]

        let retriever = CodebaseIndexRAGRetriever(index: index)
        let result = await retriever.retrieve(RAGRetrievalRequest(userInput: "runTask runner", projectRoot: projectRoot))

        XCTAssertEqual(result.symbolLines.count, 1)
        XCTAssertTrue(result.symbolLines[0].contains("runTask"))
    }

    // MARK: - Combined retrieval

    func testFullRetrievalCombinesAllSources() async {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let index = FakeRAGCodebaseIndex()
        index.stubbedSummaries = [
            (path: "\(projectRoot.path)/README.md", summary: "Project readme")
        ]
        index.stubbedSymbolResults = [
            SymbolSearchResult(
                symbol: Symbol(
                    id: UUID().uuidString,
                    resourceId: "res1",
                    name: "AppDelegate",
                    kind: .class,
                    lineStart: 1,
                    lineEnd: 50,
                    description: nil
                ),
                filePath: "\(projectRoot.path)/Sources/AppDelegate.swift"
            )
        ]

        let retriever = CodebaseIndexRAGRetriever(index: index)
        let result = await retriever.retrieve(RAGRetrievalRequest(userInput: "AppDelegate setup", projectRoot: projectRoot))

        XCTAssertFalse(result.projectOverviewLines.isEmpty)
        XCTAssertFalse(result.symbolLines.isEmpty)
    }
}

@MainActor
private final class FakeRAGCodebaseIndex: CodebaseIndexProtocol {
    var stubbedSummaries: [(path: String, summary: String)] = []
    var stubbedSymbolResults: [SymbolSearchResult] = []

    var database: DatabaseStore {
        fatalError("database not used in tests")
    }

    func start() {}
    func stop() {}
    func setEnabled(_ enabled: Bool) {}
    func reindexProject() {}

    func listIndexedFiles(matching query: String?, limit: Int, offset: Int) async throws -> [String] { [] }
    func findIndexedFiles(query: String, limit: Int) async throws -> [IndexedFileMatch] { [] }
    func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String { "" }
    func searchIndexedText(pattern: String, limit: Int) async throws -> [String] { [] }

    func searchSymbols(nameLike query: String, limit: Int) async throws -> [Symbol] {
        stubbedSymbolResults.map(\.symbol)
    }

    func searchSymbolsWithPaths(nameLike query: String, limit: Int) async throws -> [SymbolSearchResult] {
        stubbedSymbolResults
    }

    func getSummaries(projectRoot: URL, limit: Int) async throws -> [(path: String, summary: String)] {
        stubbedSummaries
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
            databaseSizeBytes: 0,
            databasePath: "",
            isDatabaseInWorkspace: false,
            averageQualityScore: 0.0,
            averageAIQualityScore: 0.0
        )
    }
}
