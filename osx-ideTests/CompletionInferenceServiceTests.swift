import XCTest
@testable import osx_ide

@MainActor
final class CompletionInferenceServiceTests: XCTestCase {
    private var defaultsSuiteName: String?

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "CompletionInferenceServiceTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let defaultsSuiteName {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testAutomaticLocalOnlyReturnsNilWhenOfflineModeIsDisabled() async throws {
        let provider = AIServiceInlineCompletionProvider(
            aiServiceProvider: { TestAIService() },
            offlineModeChecker: TestOfflineModeChecker(isOfflineModeEnabled: false)
        )

        let result = try await provider.complete(
            prompt: "return a value",
            triggerReason: .automatic,
            routingMode: .localOnly
        )

        XCTAssertNil(result)
    }

    func testManualRemoteOnlyUsesProviderOutput() async throws {
        let provider = AIServiceInlineCompletionProvider(
            aiServiceProvider: { TestAIService(result: "completion") },
            offlineModeChecker: TestOfflineModeChecker(isOfflineModeEnabled: false)
        )

        let result = try await provider.complete(
            prompt: "return a value",
            triggerReason: .manual,
            routingMode: .remoteOnly
        )

        XCTAssertEqual(result?.text, "completion")
        XCTAssertEqual(result?.source, .remote)
    }

    func testHybridPreferLocalUsesLocalServiceWhenModelSelected() async throws {
        let defaults = UserDefaults(suiteName: defaultsSuiteName!)!
        defaults.removePersistentDomain(forName: defaultsSuiteName!)
        let settingsStore = SettingsStore(userDefaults: defaults)
        let selectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        await selectionStore.setSelectedModelId("local-model")

        let provider = AIServiceInlineCompletionProvider(
            remoteServiceProvider: { TestAIService(result: "remote") },
            localServiceProvider: { TestAIService(result: "local") },
            localModelSelectionStore: selectionStore
        )

        let result = try await provider.complete(
            prompt: "return a value",
            triggerReason: .automatic,
            routingMode: .hybridPreferLocal
        )

        XCTAssertEqual(result?.text, "local")
        XCTAssertEqual(result?.source, .local)
    }
}

@MainActor
private final class TestOfflineModeChecker: OfflineModeChecking {
    private let offlineModeEnabled: Bool

    init(isOfflineModeEnabled: Bool) {
        self.offlineModeEnabled = isOfflineModeEnabled
    }

    func isOfflineModeEnabled() async -> Bool {
        offlineModeEnabled
    }
}

private actor TestAIService: AIService {
    private let result: String

    init(result: String = "completion") {
        self.result = result
    }

    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
        fatalError("unused")
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        fatalError("unused")
    }

    func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
        fatalError("unused")
    }

    func explainCode(_ code: String) async throws -> String {
        fatalError("unused")
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        fatalError("unused")
    }

    func generateCode(_ prompt: String) async throws -> String {
        result
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        fatalError("unused")
    }
}
