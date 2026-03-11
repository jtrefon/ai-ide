import XCTest
@testable import osx_ide

@MainActor
final class IndexStatusBarViewModelTests: XCTestCase {
    func testEmbeddingModelLabelRefreshesAfterAsyncUpgradeWithoutEvents() {
        let index = FakeCodebaseIndex(currentEmbeddingModelIdentifier: "hashing_v1")
        let viewModel = IndexStatusBarViewModel(
            codebaseIndexProvider: { index },
            eventBus: EventBus(),
            statsPollInterval: 0.1
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(viewModel.embeddingModelIdentifier, "hashing")

        index.currentEmbeddingModelIdentifier = "bert_nomic-embed-text-v1.5"

        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(viewModel.embeddingModelIdentifier, "nomic")
    }
}

@MainActor
private final class FakeCodebaseIndex: CodebaseIndexProtocol {
    var currentEmbeddingModelIdentifier: String

    init(currentEmbeddingModelIdentifier: String) {
        self.currentEmbeddingModelIdentifier = currentEmbeddingModelIdentifier
    }

    func start() {}
    func stop() {}
    func setEnabled(_ enabled: Bool) {}
    func reindexProject() {}
    func reindexProject(aiEnrichmentEnabled: Bool) {}
    func runAIEnrichment() {}
    func upgradeEmbeddingGenerator(_ generator: any MemoryEmbeddingGenerating) {}

    func listIndexedFiles(matching query: String?, limit: Int, offset: Int) async throws -> [String] { [] }
    func findIndexedFiles(query: String, limit: Int) async throws -> [IndexedFileMatch] { [] }
    func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String { "" }
    func searchIndexedText(pattern: String, limit: Int) async throws -> [String] { [] }
    func searchSymbols(nameLike query: String, limit: Int) async throws -> [Symbol] { [] }
    func searchSymbolsWithPaths(nameLike query: String, limit: Int) async throws -> [SymbolSearchResult] { [] }
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
            averageQualityScore: 0,
            averageAIQualityScore: 0
        )
    }
}
