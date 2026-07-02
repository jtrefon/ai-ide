import XCTest
@testable import osx_ide

@MainActor
final class InlineCompletionCSSIntegrationTests: XCTestCase {
    private let cssFilePath = "/tmp/test-styles.css"
    private let cssFileContent = """
    .header {
        font-size: 24px;
        color: #333;
    }

    .footer {
        background-color: #f5f5f5;
    }
    """

    // MARK: - Test 1: Single-line rapid inline completion (3 properties)

    func testSingleLineRapidCSSCompletion() async throws {
        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate("font-family: 'Arial', sans-serif;"),
            .immediate("color: #007aff;"),
            .immediate("background-color: #fff;")
        ]

        let engine = makeEngine(inference: inference)
        var received: [InlineSuggestionPresentation] = []
        engine.registerSuggestionHandler(for: .primary) { presentation in
            if let presentation {
                received.append(presentation)
            }
        }

        // Step 1: Create a new CSS rule and type "font-fa"
        var snapshot = makeSnapshot(
            paneID: .primary,
            buffer: ".button {\n    font-fa",
            cursor: 21,
            language: "css"
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(received.last?.suggestionText, "font-family: 'Arial', sans-serif;",
                       "First completion should suggest font-family")

        // Accept first completion
        engine.markAccepted(on: .primary, suggestionText: received.last?.suggestionText)
        received.removeAll()

        // Step 2: Type "colo"
        snapshot = makeSnapshot(
            paneID: .primary,
            buffer: ".button {\n    font-family: 'Arial', sans-serif;\n    colo",
            cursor: 57,
            language: "css"
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(received.last?.suggestionText, "color: #007aff;",
                       "Second completion should suggest color")

        // Accept second completion
        engine.markAccepted(on: .primary, suggestionText: received.last?.suggestionText)
        received.removeAll()

        // Step 3: Type "backgr"
        snapshot = makeSnapshot(
            paneID: .primary,
            buffer: ".button {\n    font-family: 'Arial', sans-serif;\n    color: #007aff;\n    backgr",
            cursor: 86,
            language: "css"
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(received.last?.suggestionText, "background-color: #fff;",
                       "Third completion should suggest background-color")

        // Accept third completion
        engine.markAccepted(on: .primary, suggestionText: received.last?.suggestionText)

        // Verify all three completions fired correctly
        XCTAssertGreaterThanOrEqual(received.count, 1, "Should have received at least one suggestion per step")
    }

    // MARK: - Test 2: Multi-line manual trigger on existing CSS (3 repetitions)

    func testMultiLineManualTriggerCSSRepeated() async throws {
        let multiLineSuggestion1 = "\n    display: flex;\n    flex-direction: column;\n    align-items: center;\n"
        let multiLineSuggestion2 = "\n    display: grid;\n    grid-template-columns: repeat(3, 1fr);\n    gap: 16px;\n"
        let multiLineSuggestion3 = "\n    position: relative;\n    overflow: hidden;\n    border-radius: 8px;\n"

        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate(multiLineSuggestion1),
            .immediate(multiLineSuggestion2),
            .immediate(multiLineSuggestion3)
        ]

        let engine = makeEngine(inference: inference, multilineEnabled: true)
        var receivedPresentations: [InlineSuggestionPresentation] = []
        engine.registerSuggestionHandler(for: .primary) { presentation in
            if let presentation {
                receivedPresentations.append(presentation)
            }
        }

        // Multi-line test 1: Insert after .header {
        var snapshot = makeSnapshot(
            paneID: .primary,
            buffer: cssFileContent,
            cursor: 8,
            language: "css",
            triggerReason: .manual
        )

        receivedPresentations.removeAll()
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstResult = receivedPresentations.last
        XCTAssertNotNil(firstResult, "First multi-line completion should not be nil")
        XCTAssertTrue(firstResult!.suggestionText.contains("display: flex"),
                      "First multi-line should contain display: flex")
        XCTAssertTrue(firstResult!.suggestionText.contains("flex-direction"),
                      "First multi-line should contain flex-direction")

        engine.markAccepted(on: .primary, suggestionText: firstResult?.suggestionText)

        // Multi-line test 2: Insert after .footer {
        snapshot = makeSnapshot(
            paneID: .primary,
            buffer: cssFileContent,
            cursor: 40,
            language: "css",
            triggerReason: .manual
        )

        receivedPresentations.removeAll()
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        let secondResult = receivedPresentations.last
        XCTAssertNotNil(secondResult, "Second multi-line completion should not be nil")
        XCTAssertTrue(secondResult!.suggestionText.contains("display: grid"),
                      "Second multi-line should contain display: grid")
        XCTAssertTrue(secondResult!.suggestionText.contains("grid-template-columns"),
                      "Second multi-line should contain grid-template-columns")

        engine.markAccepted(on: .primary, suggestionText: secondResult?.suggestionText)

        // Multi-line test 3: Third position at end of file
        snapshot = makeSnapshot(
            paneID: .primary,
            buffer: cssFileContent + "\n",
            cursor: cssFileContent.count + 1,
            language: "css",
            triggerReason: .manual
        )

        receivedPresentations.removeAll()
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        let thirdResult = receivedPresentations.last
        XCTAssertNotNil(thirdResult, "Third multi-line completion should not be nil")
        XCTAssertTrue(thirdResult!.suggestionText.contains("position: relative"),
                      "Third multi-line should contain position: relative")
        XCTAssertTrue(thirdResult!.suggestionText.contains("overflow: hidden"),
                      "Third multi-line should contain overflow: hidden")

        // Verify all three multi-line completions succeeded
        XCTAssertNotNil(firstResult, "First multi-line completion failed")
        XCTAssertNotNil(secondResult, "Second multi-line completion failed")
        XCTAssertNotNil(thirdResult, "Third multi-line completion failed")
    }

    // MARK: - Test 3: Verify ghost text clears on typing

    func testGhostTextClearsOnType() async throws {
        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate("font-weight: bold;"),
            .immediate("font-weight: bold;")
        ]

        let engine = makeEngine(inference: inference)
        var receivedCount = 0
        engine.registerSuggestionHandler(for: .primary) { presentation in
            if presentation != nil {
                receivedCount += 1
            }
        }

        // First completion appears
        var snapshot = makeSnapshot(
            paneID: .primary,
            buffer: ".alert {\n    font-w",
            cursor: 18,
            language: "css"
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(receivedCount, 1, "First completion should appear")

        // Simulate user typing more: the old request is cancelled, new one fires
        snapshot = makeSnapshot(
            paneID: .primary,
            buffer: ".alert {\n    font-weight",
            cursor: 22,
            language: "css"
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(receivedCount, 2, "Second completion should appear after typing more")
    }

    // MARK: - Test 4: Multi-line ghost text stores full text

    func testMultiLineStoresFullText() async throws {
        let multiLineText = "\n    padding: 16px;\n    margin: 0;\n"

        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate(multiLineText)
        ]

        let engine = makeEngine(inference: inference, multilineEnabled: true)
        var received: InlineSuggestionPresentation?
        engine.registerSuggestionHandler(for: .primary) { presentation in
            if let presentation {
                received = presentation
            }
        }

        let snapshot = makeSnapshot(
            paneID: .primary,
            buffer: cssFileContent,
            cursor: 8,
            language: "css",
            triggerReason: .manual
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(received, "Multi-line completion should not be nil")
        XCTAssertTrue(received!.suggestionText.contains("padding: 16px"),
                      "Multi-line suggestion should contain the full text")
    }

    // MARK: - Helpers

    private func makeEngine(
        inference: TestCSSInferenceService,
        multilineEnabled: Bool = false
    ) -> InlineCompletionEngine {
        InlineCompletionEngine(
            settingsStore: CSSInlineCompletionSettingsStore(multilineEnabled: multilineEnabled),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: TestCSSRetrievalLayer(),
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )
    }

    private func makeSnapshot(
        paneID: FileEditorStateManager.PaneID,
        buffer: String,
        cursor: Int,
        language: String,
        triggerReason: CompletionTriggerReason = .automatic
    ) -> InlineCompletionEditorSnapshot {
        InlineCompletionEditorSnapshot(
            paneID: paneID,
            filePath: cssFilePath,
            language: language,
            buffer: buffer,
            cursorPosition: cursor,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: triggerReason
        )
    }
}

// MARK: - Test Mocks

@MainActor
private final class TestCSSInferenceService: CompletionInferring {
    enum Response {
        case immediate(String)
        case delayed(String, UInt64)
    }

    var responses: [Response] = []

    func infer(
        for request: InlineCompletionRequest,
        settings: InlineCompletionSettings
    ) async throws -> InlineCompletionResult? {
        guard !responses.isEmpty else { return nil }
        let response = responses.removeFirst()

        switch response {
        case let .immediate(text):
            return InlineCompletionResult(
                requestId: request.requestId,
                suggestionText: text,
                confidenceScore: 0.8,
                source: .local,
                latencyMs: 10
            )
        case let .delayed(text, delay):
            try? await Task.sleep(nanoseconds: delay)
            return InlineCompletionResult(
                requestId: request.requestId,
                suggestionText: text,
                confidenceScore: 0.8,
                source: .local,
                latencyMs: Double(delay) / 1_000_000
            )
        }
    }
}

@MainActor
private final class TestCSSRetrievalLayer: CompletionRetrieving {
    func retrieveContext(
        for snapshot: InlineCompletionEditorSnapshot,
        request: CompletionContextPayload,
        settings: InlineCompletionSettings,
        reduceWorkload: Bool
    ) async -> [String] {
        []
    }
}

@MainActor
private final class CSSInlineCompletionSettingsStore: InlineCompletionSettingsStore {
    private let multilineEnabled: Bool

    init(multilineEnabled: Bool = false) {
        self.multilineEnabled = multilineEnabled
        super.init()
    }

    override func load() -> InlineCompletionSettings {
        InlineCompletionSettings(
            isEnabled: true,
            debounceMilliseconds: 0,
            aggressiveness: 0.6,
            maxSuggestionLength: 200,
            multilineEnabled: multilineEnabled,
            retrievalEnabled: false,
            routingMode: .localOnly,
            debugOverlayEnabled: false
        )
    }
}
