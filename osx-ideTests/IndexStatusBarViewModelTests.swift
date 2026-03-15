import XCTest
@testable import osx_ide

@MainActor
final class IndexStatusBarViewModelTests: XCTestCase {
    func testEmbeddingModelLabelRefreshesAfterAsyncUpgradeWithoutEvents() {
        let index = FakeCodebaseIndex(currentEmbeddingModelIdentifier: "hashing_v1")
        let viewModel = IndexStatusBarViewModel(
            codebaseIndexProvider: { index },
            eventBus: EventBus(),
            refreshRemoteAIAccountBalance: { _ in },
            statsPollInterval: 0.1
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(viewModel.embeddingModelIdentifier, "hashing")

        index.currentEmbeddingModelIdentifier = "bert_nomic-embed-text-v1.5"

        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(viewModel.embeddingModelIdentifier, "nomic")
    }

    func testRemoteAIUsageDisplaysBalanceWhenProvided() {
        let eventBus = EventBus()
        let viewModel = IndexStatusBarViewModel(
            codebaseIndexProvider: { FakeCodebaseIndex(currentEmbeddingModelIdentifier: "hashing_v1") },
            eventBus: eventBus,
            refreshRemoteAIAccountBalance: { _ in },
            statsPollInterval: 60
        )

        eventBus.publish(OpenRouterUsageUpdatedEvent(
            providerName: "Kilo Code",
            modelId: "kilo-auto/balanced",
            runId: "run-1",
            usage: .init(
                promptTokens: 10,
                completionTokens: 20,
                totalTokens: 30,
                costMicrodollars: 120_000,
                accountBalanceMicrodollars: 13_450_000
            ),
            contextLength: 100
        ))

        XCTAssertEqual(viewModel.openRouterContextUsageText, "CTX 30/100")
        XCTAssertEqual(viewModel.remoteAICostText, "")
        XCTAssertEqual(viewModel.remoteAISpendText, "Kilo Code spent $0.12")
        XCTAssertEqual(viewModel.remoteAIBalanceText, "Kilo Code balance $13.45")
    }

    func testConversationCompletionTriggersDelayedBalanceRefresh() {
        let eventBus = EventBus()
        let refreshExpectation = expectation(description: "refresh balance")
        let viewModel = IndexStatusBarViewModel(
            codebaseIndexProvider: { FakeCodebaseIndex(currentEmbeddingModelIdentifier: "hashing_v1") },
            eventBus: eventBus,
            refreshRemoteAIAccountBalance: { runId in
                if runId == "run-42" {
                    refreshExpectation.fulfill()
                }
            },
            statsPollInterval: 60
        )

        _ = viewModel
        eventBus.publish(ConversationRunCompletedEvent(runId: "run-42"))

        wait(for: [refreshExpectation], timeout: 3.0)
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
    func getRelevantCodeChunks(userInput: String, limit: Int) async throws -> [CodeChunkSimilarityResult] {
        _ = userInput
        _ = limit
        return []
    }

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
