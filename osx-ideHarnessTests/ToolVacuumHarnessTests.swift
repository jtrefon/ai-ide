import XCTest
@testable import osx_ide

@MainActor
final class ToolVacuumHarnessTests: XCTestCase {
    private final class MockCodebaseIndex: CodebaseIndexProtocol {
        var database: DatabaseStore
        var mockListFilesResult: [String] = []
        var mockReadFileResult: String = ""
        var mockSearchTextResult: [String] = []
        var mockSearchSymbolsWithPathsResult: [SymbolSearchResult] = []

        init() {
            database = try! DatabaseStore(path: "/tmp/test_tool_vacuum_\(UUID().uuidString).db")
        }

        func start() {}
        func stop() {}
        func setEnabled(_ enabled: Bool) {}
        func reindexProject() {}
        func listIndexedFiles(matching query: String?, limit: Int, offset: Int) async throws -> [String] {
            mockListFilesResult
        }
        func findIndexedFiles(query: String, limit: Int) async throws -> [IndexedFileMatch] { [] }
        func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String {
            mockReadFileResult
        }
        func searchIndexedText(pattern: String, limit: Int) async throws -> [String] {
            mockSearchTextResult
        }
        func searchSymbols(nameLike query: String, limit: Int) async throws -> [Symbol] { [] }
        func searchSymbolsWithPaths(nameLike query: String, limit: Int) async throws -> [SymbolSearchResult] {
            mockSearchSymbolsWithPathsResult
        }
        func getSummaries(projectRoot: URL, limit: Int) async throws -> [(path: String, summary: String)] { [] }
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

    func testCoreFileToolLifecycleInIsolation() async throws {
        let projectRoot = makeTempDir(prefix: "tool_vacuum_lifecycle")
        defer { cleanup(projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let eventBus = EventBus()
        let fileSystemService = FileSystemService()

        let writeFileTool = WriteFileTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator,
            eventBus: eventBus
        )
        let readFileTool = ReadFileTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator
        )
        let replaceInFileTool = ReplaceInFileTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator,
            eventBus: eventBus
        )
        let listFilesTool = ListFilesTool(pathValidator: pathValidator)
        let deleteFileTool = DeleteFileTool(pathValidator: pathValidator, eventBus: eventBus)

        let writeResult = try await writeFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx",
            "content": "export default function App() {\n    return <div>Todo</div>\n}\n",
            "_conversation_id": "tool-vacuum-lifecycle"
        ]))
        XCTAssertTrue(writeResult.localizedCaseInsensitiveContains("successfully wrote"))

        let readResult = try await readFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx",
            "_conversation_id": "tool-vacuum-lifecycle"
        ]))
        XCTAssertTrue(readResult.contains("App"))
        XCTAssertTrue(readResult.contains("Todo"))

        let replaceResult = try await replaceInFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx",
            "old_text": "Todo",
            "new_text": "Tasks"
        ]))
        XCTAssertTrue(replaceResult.localizedCaseInsensitiveContains("successfully"))

        let listedFiles = try await listFilesTool.execute(arguments: ToolArguments([
            "path": "src"
        ]))
        XCTAssertTrue(listedFiles.contains("App.jsx"))

        let persistedContent = try String(
            contentsOf: projectRoot.appendingPathComponent("src/App.jsx"),
            encoding: .utf8
        )
        XCTAssertTrue(persistedContent.contains("Tasks"))

        let deleteResult = try await deleteFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx"
        ]))
        XCTAssertTrue(deleteResult.localizedCaseInsensitiveContains("deleted"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("src/App.jsx").path))
    }

    func testBatchWriteAndListRemainConsistentInIsolation() async throws {
        let projectRoot = makeTempDir(prefix: "tool_vacuum_batch")
        defer { cleanup(projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let eventBus = EventBus()
        let fileSystemService = FileSystemService()

        let writeFileTool1 = WriteFileTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator,
            eventBus: eventBus
        )
        let writeFileTool2 = WriteFileTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator,
            eventBus: eventBus
        )
        let readFileTool = ReadFileTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator
        )
        let listFilesTool = ListFilesTool(pathValidator: pathValidator)

        let result1 = try await writeFileTool1.execute(arguments: ToolArguments([
            "path": "src/main.jsx",
            "content": "import App from './App'\n",
            "_conversation_id": "tool-vacuum-batch"
        ]))
        XCTAssertTrue(result1.localizedCaseInsensitiveContains("successfully wrote"))

        let result2 = try await writeFileTool2.execute(arguments: ToolArguments([
            "path": "src/App.jsx",
            "content": "export default function App() { return null }\n",
            "_conversation_id": "tool-vacuum-batch"
        ]))
        XCTAssertTrue(result2.localizedCaseInsensitiveContains("successfully wrote"))

        let mainFileRead = try await readFileTool.execute(arguments: ToolArguments([
            "path": "src/main.jsx",
            "_conversation_id": "tool-vacuum-batch"
        ]))
        XCTAssertTrue(mainFileRead.contains("import App"))

        let listResult = try await listFilesTool.execute(arguments: ToolArguments([
            "path": "src"
        ]))
        XCTAssertTrue(listResult.contains("main.jsx"))
        XCTAssertTrue(listResult.contains("App.jsx"))
    }

    private func makeTempDir(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
      }
}
