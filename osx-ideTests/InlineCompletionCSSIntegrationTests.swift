import XCTest
@testable import osx_ide

@MainActor
final class InlineCompletionCSSIntegrationTests: XCTestCase {

    // MARK: - Single-line completion: 3 sequential tests

    func testSingleLine_1_firstCompletionInsertsSingleLine() async throws {
        let inference = TestCSSInferenceService()
        inference.responses = [.immediate("font-family: 'Arial', sans-serif;")]

        let engine = makeEngine(inference: inference)
        var received: InlineSuggestionPresentation?
        engine.registerSuggestionHandler(for: .primary) { presentation in
            if let presentation { received = presentation }
        }

        let snapshot = makeSnapshot(
            buffer: ".button {\n    font-fa",
            cursor: 21
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(received, "Single-line completion should not be nil")
        XCTAssertFalse(received!.suggestionText.contains("\n"),
                       "Single-line completion should not contain newlines")
    }

    func testSingleLine_2_secondCompletionAfterAccept() async throws {
        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate("font-family: 'Arial', sans-serif;"),
            .immediate("color: #007aff;")
        ]

        let engine = makeEngine(inference: inference)
        var received: InlineSuggestionPresentation?
        let callback = { (presentation: InlineSuggestionPresentation?) in
            if let p = presentation { received = p }
        }
        engine.registerSuggestionHandler(for: .primary, handler: callback)

        // First completion
        engine.requestCompletion(for: makeSnapshot(buffer: ".button {\n    font-fa", cursor: 21))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotNil(received, "First single-line completion should not be nil")
        engine.markAccepted(on: .primary, suggestionText: received?.suggestionText)

        // Second completion — different property
        received = nil
        engine.requestCompletion(for: makeSnapshot(buffer: ".button {\n    font-family: 'Arial', sans-serif;\n    colo", cursor: 57))
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(received, "Second single-line completion after accept should not be nil")
        XCTAssertFalse(received!.suggestionText.contains("\n"),
                       "Second single-line completion should not contain newlines")
    }

    func testSingleLine_3_thirdCompletionAfterTwoAccepts() async throws {
        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate("font-family: 'Arial', sans-serif;"),
            .immediate("color: #007aff;"),
            .immediate("background-color: #fff;")
        ]

        let engine = makeEngine(inference: inference)
        var received: InlineSuggestionPresentation?
        let callback = { (presentation: InlineSuggestionPresentation?) in
            if let p = presentation { received = p }
        }
        engine.registerSuggestionHandler(for: .primary, handler: callback)

        // First
        engine.requestCompletion(for: makeSnapshot(buffer: ".button {\n    font-fa", cursor: 21))
        try await Task.sleep(nanoseconds: 80_000_000)
        engine.markAccepted(on: .primary, suggestionText: received?.suggestionText)

        // Second
        received = nil
        engine.requestCompletion(for: makeSnapshot(buffer: ".button {\n    font-family: 'Arial', sans-serif;\n    colo", cursor: 57))
        try await Task.sleep(nanoseconds: 80_000_000)
        engine.markAccepted(on: .primary, suggestionText: received?.suggestionText)

        // Third — different property entirely
        received = nil
        engine.requestCompletion(for: makeSnapshot(buffer: ".button {\n    font-family: 'Arial', sans-serif;\n    color: #007aff;\n    backgr", cursor: 86))
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(received, "Third single-line completion after two accepts should not be nil")
        XCTAssertEqual(received!.suggestionText, "background-color: #fff;",
                       "Third completion should suggest background-color")
        XCTAssertFalse(received!.suggestionText.contains("\n"),
                       "Third single-line completion should not contain newlines")
    }

    // MARK: - Multi-line manual trigger: 3 sequential tests

    func testMultiLine_1_firstManualTriggerReturnsMultiLine() async throws {
        let inference = TestCSSInferenceService()
        let multiLineText = "\n    display: flex;\n    flex-direction: column;\n    align-items: center;\n"
        inference.responses = [.immediate(multiLineText)]

        let engine = makeEngine(inference: inference)
        var received: InlineSuggestionPresentation?
        engine.registerSuggestionHandler(for: .primary) { presentation in
            if let p = presentation { received = p }
        }

        let snapshot = makeSnapshot(
            buffer: ".header {\n    font-size: 24px;\n    color: #333;\n}",
            cursor: 8,
            triggerReason: .manual
        )
        engine.requestCompletion(for: snapshot)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(received, "First multi-line completion should not be nil")
        XCTAssertTrue(received!.suggestionText.contains("display: flex"),
                      "Multi-line should contain display: flex")
        XCTAssertTrue(received!.suggestionText.contains("flex-direction"),
                      "Multi-line should contain flex-direction")
    }

    func testMultiLine_2_secondManualTriggerAfterAccept() async throws {
        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate("\n    display: flex;\n    flex-direction: column;\n    align-items: center;\n"),
            .immediate("\n    display: grid;\n    grid-template-columns: repeat(3, 1fr);\n    gap: 16px;\n")
        ]

        let engine = makeEngine(inference: inference)
        var received: InlineSuggestionPresentation?
        let callback = { (presentation: InlineSuggestionPresentation?) in
            if let p = presentation { received = p }
        }
        engine.registerSuggestionHandler(for: .primary, handler: callback)

        // First multi-line
        engine.requestCompletion(for: makeSnapshot(buffer: cssFixture, cursor: 8, triggerReason: .manual))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotNil(received, "First multi-line should not be nil")
        engine.markAccepted(on: .primary, suggestionText: received?.suggestionText)

        // Second multi-line — different content
        received = nil
        engine.requestCompletion(for: makeSnapshot(buffer: cssFixture, cursor: 40, triggerReason: .manual))
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(received, "Second multi-line after accept should not be nil")
        XCTAssertTrue(received!.suggestionText.contains("display: grid"),
                      "Second multi-line should contain display: grid")
    }

    func testMultiLine_3_thirdManualTriggerAfterTwoAccepts() async throws {
        let inference = TestCSSInferenceService()
        inference.responses = [
            .immediate("\n    display: flex;\n    flex-direction: column;\n    align-items: center;\n"),
            .immediate("\n    display: grid;\n    grid-template-columns: repeat(3, 1fr);\n    gap: 16px;\n"),
            .immediate("\n    position: relative;\n    overflow: hidden;\n    border-radius: 8px;\n")
        ]

        let engine = makeEngine(inference: inference)
        var received: InlineSuggestionPresentation?
        let callback = { (presentation: InlineSuggestionPresentation?) in
            if let p = presentation { received = p }
        }
        engine.registerSuggestionHandler(for: .primary, handler: callback)

        // First
        engine.requestCompletion(for: makeSnapshot(buffer: cssFixture, cursor: 8, triggerReason: .manual))
        try await Task.sleep(nanoseconds: 80_000_000)
        engine.markAccepted(on: .primary, suggestionText: received?.suggestionText)

        // Second
        received = nil
        engine.requestCompletion(for: makeSnapshot(buffer: cssFixture, cursor: 40, triggerReason: .manual))
        try await Task.sleep(nanoseconds: 80_000_000)
        engine.markAccepted(on: .primary, suggestionText: received?.suggestionText)

        // Third
        received = nil
        engine.requestCompletion(for: makeSnapshot(buffer: cssFixture, cursor: cssFixture.count, triggerReason: .manual))
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(received, "Third multi-line after two accepts should not be nil")
        XCTAssertTrue(received!.suggestionText.contains("position: relative"),
                      "Third multi-line should contain position: relative")
        XCTAssertTrue(received!.suggestionText.contains("border-radius"),
                      "Third multi-line should contain border-radius")
    }

    // MARK: - Helpers

    private let cssFixture = """
    .header {
        font-size: 24px;
        color: #333;
    }

    .footer {
        background-color: #f5f5f5;
    }
    """

    private func makeEngine(inference: TestCSSInferenceService) -> InlineCompletionEngine {
        InlineCompletionEngine(
            settingsStore: CSSInlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: TestCSSRetrievalLayer(),
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )
    }

    private func makeSnapshot(
        buffer: String,
        cursor: Int,
        triggerReason: CompletionTriggerReason = .automatic
    ) -> InlineCompletionEditorSnapshot {
        InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/test-styles.css",
            language: "css",
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
    override func load() -> InlineCompletionSettings {
        InlineCompletionSettings(
            isEnabled: true,
            debounceMilliseconds: 0,
            aggressiveness: 0.6,
            maxSuggestionLength: 200,
            multilineEnabled: true,
            retrievalEnabled: false,
            routingMode: .localOnly,
            debugOverlayEnabled: false
        )
    }
}
