import XCTest
@testable import osx_ide

@MainActor
final class ToolVacuumHarnessTests: XCTestCase {
    private final class MockCodebaseIndex: CodebaseIndexProtocol {
        var currentEmbeddingModelIdentifier: String = "hashing_v1"
        var mockListFilesResult: [String] = []
        var mockReadFileResult: String = ""
        var mockSearchTextResult: [String] = []
        var mockSearchSymbolsWithPathsResult: [SymbolSearchResult] = []
        var mockMemoriesResult: [MemoryEntry] = []

        func start() {}
        func stop() {}
        func setEnabled(_ enabled: Bool) {}
        func reindexProject() {}
        func reindexProject(aiEnrichmentEnabled: Bool) {}
        func runAIEnrichment() {}
        func upgradeEmbeddingGenerator(_ generator: any MemoryEmbeddingGenerating) {}
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
        func getMemories(tier: MemoryTier?) async throws -> [MemoryEntry] {
            guard let tier else { return mockMemoriesResult }
            return mockMemoriesResult.filter { $0.tier == tier }
        }
        func addMemory(content: String, tier: MemoryTier, category: String) async throws -> MemoryEntry {
            let entry = MemoryEntry(
                id: UUID().uuidString,
                tier: tier,
                content: content,
                category: category,
                timestamp: Date(),
                protectionLevel: 0
            )
            mockMemoriesResult.insert(entry, at: 0)
            return entry
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
    }

    func testCoreFileToolLifecycleInIsolation() async throws {
        let projectRoot = makeTempDir(prefix: "tool_vacuum_lifecycle")
        defer { cleanup(projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let eventBus = EventBus()
        let fileSystemService = FileSystemService()

        let createFileTool = CreateFileTool(pathValidator: pathValidator, eventBus: eventBus)
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

        let reservationResult = try await createFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx"
        ]))
        XCTAssertTrue(reservationResult.localizedCaseInsensitiveContains("reserved file path"))

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

        let writeFilesTool = WriteFilesTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator,
            eventBus: eventBus
        )
        let readFileTool = ReadFileTool(
            fileSystemService: fileSystemService,
            pathValidator: pathValidator
        )
        let listFilesTool = ListFilesTool(pathValidator: pathValidator)

        let batchResult = try await writeFilesTool.execute(arguments: ToolArguments([
            "files": [
                [
                    "path": "src/main.jsx",
                    "content": "import App from './App'\n"
                ],
                [
                    "path": "src/App.jsx",
                    "content": "export default function App() { return null }\n"
                ]
            ]
        ]))

        XCTAssertTrue(batchResult.localizedCaseInsensitiveContains("successfully wrote 2 file(s)"))

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

    func testIndexToolsExposeStableAuthoritativeResultsInIsolation() async throws {
        let mockIndex = MockCodebaseIndex()
        mockIndex.mockListFilesResult = [
            "src/App.jsx",
            "src/main.jsx"
        ]
        mockIndex.mockReadFileResult = [
            "1 | export default function App() {",
            "2 |   return <div>Hello Vacuum</div>",
            "3 | }"
        ].joined(separator: "\n")
        mockIndex.mockSearchTextResult = [
            "src/App.jsx:2:   return <div>Hello Vacuum</div>"
        ]
        mockIndex.mockSearchSymbolsWithPathsResult = [
            SymbolSearchResult(
                symbol: Symbol(
                    id: UUID().uuidString,
                    resourceId: "resource-src-app",
                    name: "App",
                    kind: .function,
                    lineStart: 1,
                    lineEnd: 3,
                    description: nil
                ),
                filePath: "src/App.jsx"
            )
        ]

        let indexListFilesTool = IndexListFilesTool(index: mockIndex)
        let indexReadFileTool = IndexReadFileTool(index: mockIndex)
        let indexSearchTextTool = IndexSearchTextTool(index: mockIndex)
        let indexSearchSymbolsTool = IndexSearchSymbolsTool(index: mockIndex)

        let listedFiles = try await indexListFilesTool.execute(arguments: ToolArguments([
            "query": "src",
            "limit": 10,
            "offset": 0
        ]))
        XCTAssertTrue(listedFiles.contains("src/App.jsx"))
        XCTAssertTrue(listedFiles.contains("src/main.jsx"))

        let readResult = try await indexReadFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx",
            "start_line": 1,
            "end_line": 3,
            "_conversation_id": "tool-vacuum-index"
        ]))
        XCTAssertTrue(readResult.contains("Hello Vacuum"))

        let textSearchResult = try await indexSearchTextTool.execute(arguments: ToolArguments([
            "pattern": "Hello Vacuum",
            "limit": 10
        ]))
        XCTAssertTrue(textSearchResult.contains("src/App.jsx:2:"))

        let symbolSearchResult = try await indexSearchSymbolsTool.execute(arguments: ToolArguments([
            "query": "App",
            "limit": 10
        ]))
        XCTAssertTrue(symbolSearchResult.contains("[function] App"))
        XCTAssertTrue(symbolSearchResult.contains("src/App.jsx:1-3"))
    }

    func testPlanningToolsProduceStructuredPlansInIsolation() async throws {
        let plannerTool = PlannerTool()
        let strategicPlanTool = StrategicPlanTool()
        let tacticalPlanTool = TacticalPlanTool()

        let plannerResult = try await plannerTool.execute(arguments: ToolArguments([
            "action": "set",
            "plan": "# Implementation Plan\n\n- [ ] Validate isolated tools\n",
            "_conversation_id": "tool-vacuum-plan"
        ]))
        XCTAssertTrue(plannerResult.contains("Implementation Plan"))

        let strategicResult = try await strategicPlanTool.execute(arguments: ToolArguments([
            "userInput": "Validate basic tool execution coverage for the local agent pipeline"
        ]))
        XCTAssertTrue(strategicResult.contains("# Implementation Plan"))
        XCTAssertTrue(strategicResult.contains("Goal:"))

        let tacticalResult = try await tacticalPlanTool.execute(arguments: ToolArguments([
            "strategicPlan": strategicResult,
            "userInput": "Validate basic tool execution coverage for the local agent pipeline"
        ]))
        XCTAssertTrue(tacticalResult.contains("Use read_file/list_files to inspect relevant sources"))
        XCTAssertTrue(tacticalResult.contains("Apply edits using write_file/replace_in_file"))
    }

    func testIndexMemoryToolsPersistAndListStableResultsInIsolation() async throws {
        let mockIndex = MockCodebaseIndex()
        let addMemoryTool = IndexAddMemoryTool(index: mockIndex)
        let listMemoriesTool = IndexListMemoriesTool(index: mockIndex)

        let addResult = try await addMemoryTool.execute(arguments: ToolArguments([
            "content": "Planner output should remain concise and actionable",
            "tier": "longTerm",
            "category": "architecture"
        ]))
        XCTAssertTrue(addResult.contains("Memory saved:"))
        XCTAssertTrue(addResult.contains("[longTerm]"))

        let listResult = try await listMemoriesTool.execute(arguments: ToolArguments([
            "tier": "longTerm",
            "limit": 10
        ]))
        XCTAssertTrue(listResult.contains("Planner output should remain concise and actionable"))
        XCTAssertTrue(listResult.contains("category=architecture"))
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
