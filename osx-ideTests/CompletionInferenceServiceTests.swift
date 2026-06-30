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

    func testCompleteLocallyReturnsNilWhenNoFimModelAvailable() async throws {
        let defaults = UserDefaults(suiteName: defaultsSuiteName!)!
        defaults.removePersistentDomain(forName: defaultsSuiteName!)
        let settingsStore = SettingsStore(userDefaults: defaults)
        let selectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        await selectionStore.setCompletionModelId("nonexistent-fim-model-id")

        let provider = AIServiceInlineCompletionProvider(
            remoteServiceProvider: { nil },
            localServiceProvider: { nil },
            localModelSelectionStore: selectionStore
        )

        let result = try await provider.completeLocally(
            prefix: "func foo() {", suffix: "\n}", maxTokens: 40
        )

        XCTAssertNil(result, "completeLocally should return nil when FIM model cannot be loaded")
    }

    func testLocalOnlyRoutingUsesCompleteLocally() async throws {
        let recorder = PromptRecorder()
        let inferService = CompletionInferenceService(provider: recorder)

        let request = InlineCompletionRequest(
            requestId: UUID(),
            filePath: "/test.swift",
            language: "swift",
            prefix: "func foo() {",
            suffix: "\n}",
            cursorPosition: 13,
            scopeSummary: nil,
            symbols: [],
            retrievalContext: [],
            triggerReason: .manual,
            maxSuggestionLength: 40,
            allowMultiline: true
        )

        let settings = InlineCompletionSettings(
            isEnabled: true,
            debounceMilliseconds: 0,
            aggressiveness: 0.3,
            maxSuggestionLength: 40,
            multilineEnabled: false,
            retrievalEnabled: false,
            routingMode: .localOnly,
            debugOverlayEnabled: false
        )

        let result = try await inferService.infer(for: request, settings: settings)

        XCTAssertNil(result, "localOnly should return nil because PromptRecorder.completeLocally returns nil")
        XCTAssertEqual(recorder.capturedLocallyPrefix, "func foo() {")
        XCTAssertEqual(recorder.capturedLocallySuffix, "\n}")
    }
}

@MainActor
private final class PromptRecorder: InlineCompletionProviding {
    var capturedPrompt: String?
    var capturedLocallyPrefix: String?
    var capturedLocallySuffix: String?

    func complete(prompt: String, triggerReason: CompletionTriggerReason, routingMode: InlineCompletionRoutingMode) async throws -> (text: String, source: InlineCompletionSource)? {
        capturedPrompt = prompt
        return ("result", .remote)
    }

    func completeLocally(prefix: String, suffix: String, maxTokens: Int) async throws -> (text: String, source: InlineCompletionSource)? {
        capturedLocallyPrefix = prefix
        capturedLocallySuffix = suffix
        return nil
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
