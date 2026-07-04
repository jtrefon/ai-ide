import XCTest
@testable import osx_ide

@MainActor
final class IndexStatusBarViewModelTests: XCTestCase {
    func testRemoteAIUsageDisplaysBalanceWhenProvided() {
        let eventBus = EventBus()
        let viewModel = IndexStatusBarViewModel(
            codebaseIndexProvider: { FakeCodebaseIndex() },
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

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(viewModel.openRouterContextUsageText, "CTX 30/100")
        XCTAssertEqual(viewModel.remoteAICostText, "")
        XCTAssertEqual(viewModel.remoteAISpendText, "Kilo Code spent $0.12")
        XCTAssertEqual(viewModel.remoteAIBalanceText, "Kilo Code balance $13.45")
    }

    func testConversationCompletionTriggersDelayedBalanceRefresh() {
        let eventBus = EventBus()
        let refreshExpectation = expectation(description: "refresh balance")
        let viewModel = IndexStatusBarViewModel(
            codebaseIndexProvider: { FakeCodebaseIndex() },
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
    var database: DatabaseStore

    init() {
        database = try! DatabaseStore(path: "/tmp/test_statusbar_\(UUID().uuidString).db")
    }

    func start() {}
    func stop() {}
    func setEnabled(_ enabled: Bool) {}
    func reindexProject() {}

    func listIndexedFiles(matching query: String?, limit: Int, offset: Int) async throws -> [String] { [] }
    func findIndexedFiles(query: String, limit: Int) async throws -> [IndexedFileMatch] { [] }
    func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String { "" }
    func searchIndexedText(pattern: String, limit: Int) async throws -> [String] { [] }
    func searchSymbols(nameLike query: String, limit: Int) async throws -> [Symbol] { [] }
    func searchSymbolsWithPaths(nameLike query: String, limit: Int) async throws -> [SymbolSearchResult] { [] }
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
            averageQualityScore: 0,
            averageAIQualityScore: 0
        )
    }
}
