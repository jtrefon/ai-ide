import XCTest
@testable import osx_ide

/// Layer 2: InlineCompletionEngine — tests the engine's request lifecycle,
/// acceptance flow, and multi-request state management.
@MainActor
final class FIMEngineStateUnitTests: XCTestCase {

    // MARK: - Single request lifecycle

    func test_engine_immediateRequest_returnsSuggestion() async throws {
        let inference = TestEngineInferenceService()
        inference.responses = [.immediate("color: red;")]

        let engine = makeEngine(inference: inference)
        let captured = CapturedSuggestions()
        engine.registerSuggestionHandler(for: .primary) { captured.set($0) }

        engine.requestCompletion(for: snapshot(buffer: ".foo {\n    colo", cursor: 14))

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(captured.lastSuggestion, "color: red;")
    }

    func test_engine_noResponse_publishesNil() async throws {
        let inference = TestEngineInferenceService()
        inference.responses = []

        let engine = makeEngine(inference: inference)
        let captured = CapturedSuggestions()
        engine.registerSuggestionHandler(for: .primary) { captured.set($0) }

        engine.requestCompletion(for: snapshot(buffer: "foo", cursor: 3))

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(captured.lastSuggestion)
    }

    // MARK: - Sequential requests (3 in a row)

    func test_engine_threeSequentialRequests_allSucceed() async throws {
        let inference = TestEngineInferenceService()
        inference.responses = [
            .immediate("font-family: serif;"),
            .immediate("color: blue;"),
            .immediate("background: white;")
        ]

        let engine = makeEngine(inference: inference)
        let captured = CapturedSuggestions()
        engine.registerSuggestionHandler(for: .primary) { captured.set($0) }

        // Request 1
        engine.requestCompletion(for: snapshot(buffer: ".a {\n    font-fam", cursor: 16))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(captured.lastSuggestion, "font-family: serif;", "First request should succeed")

        // Accept
        engine.markAccepted(on: .primary, suggestionText: captured.lastSuggestion)

        // Request 2
        captured.reset()
        engine.requestCompletion(for: snapshot(buffer: ".a {\n    font-family: serif;\n    colo", cursor: 40))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(captured.lastSuggestion, "color: blue;", "Second request after accept should succeed")

        // Accept
        engine.markAccepted(on: .primary, suggestionText: captured.lastSuggestion)

        // Request 3
        captured.reset()
        engine.requestCompletion(for: snapshot(buffer: ".a {\n    font-family: serif;\n    color: blue;\n    backg", cursor: 63))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(captured.lastSuggestion, "background: white;", "Third request after two accepts should succeed")
    }

    // MARK: - Out-of-order (later request completes first)

    func test_engine_lateRequestWins_overEarlySlowRequest() async throws {
        let inference = TestEngineInferenceService()
        inference.responses = [
            .delayed("old", 200_000_000),
            .immediate("new")
        ]

        let engine = makeEngine(inference: inference)
        let captured = CapturedSuggestions()
        engine.registerSuggestionHandler(for: .primary) { captured.set($0) }

        engine.requestCompletion(for: snapshot(buffer: "first", cursor: 5))
        engine.requestCompletion(for: snapshot(buffer: "second", cursor: 6))

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(captured.lastSuggestion, "new", "Later request result should win")
    }

    // MARK: - Multi-line manual trigger

    func test_engine_manualTriggerWithMultiline_acceptsMultiLineResult() async throws {
        let inference = TestEngineInferenceService()
        let block = "\n    display: flex;\n    flex-direction: column;"
        inference.responses = [.immediate(block)]

        let engine = makeEngine(inference: inference, multilineEnabled: true)
        let captured = CapturedSuggestions()
        engine.registerSuggestionHandler(for: .primary) { captured.set($0) }

        let snap = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/test.css",
            language: "css",
            buffer: ".header {\n    font-size: 24px;\n}",
            cursorPosition: 8,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )
        engine.requestCompletion(for: snap)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNotNil(captured.lastSuggestion)
        XCTAssertTrue(captured.lastSuggestion!.contains("display: flex"), "Manual trigger should return multi-line content")
        XCTAssertTrue(captured.lastSuggestion!.contains("flex-direction"), "Manual trigger should return full multi-line content")
    }

    func test_engine_threeManualTriggersInARow_allSucceed() async throws {
        let inference = TestEngineInferenceService()
        inference.responses = [
            .immediate("\n    display: flex;\n    gap: 8px;"),
            .immediate("\n    display: grid;\n    gap: 16px;"),
            .immediate("\n    position: relative;\n    z-index: 10;")
        ]

        let engine = makeEngine(inference: inference, multilineEnabled: true)
        let captured = CapturedSuggestions()
        engine.registerSuggestionHandler(for: .primary) { captured.set($0) }

        func manualSnap(buffer: String, cursor: Int) -> InlineCompletionEditorSnapshot {
            InlineCompletionEditorSnapshot(paneID: .primary, filePath: "/tmp/t.css", language: "css", buffer: buffer, cursorPosition: cursor, selectionLength: 0, isComposingText: false, triggerReason: .manual)
        }

        let css = ".header {\n    color: red;\n}\n\n.footer {\n    color: blue;\n}"

        // Manual trigger 1
        captured.reset()
        engine.requestCompletion(for: manualSnap(buffer: css, cursor: 8))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(captured.lastSuggestion?.contains("display: flex") ?? false, "First manual trigger should return multi-line")
        engine.markAccepted(on: .primary, suggestionText: captured.lastSuggestion)

        // Manual trigger 2
        captured.reset()
        engine.requestCompletion(for: manualSnap(buffer: css, cursor: 39))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(captured.lastSuggestion?.contains("display: grid") ?? false, "Second manual trigger should return multi-line")
        engine.markAccepted(on: .primary, suggestionText: captured.lastSuggestion)

        // Manual trigger 3
        captured.reset()
        engine.requestCompletion(for: manualSnap(buffer: css, cursor: css.count))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(captured.lastSuggestion?.contains("position: relative") ?? false, "Third manual trigger should return multi-line")
    }

    // MARK: - Helpers

    private func makeEngine(
        inference: TestEngineInferenceService,
        multilineEnabled: Bool = false
    ) -> InlineCompletionEngine {
        InlineCompletionEngine(
            settingsStore: EngineTestSettingsStore(multilineEnabled: multilineEnabled),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: TestEngineRetrievalLayer(),
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )
    }

    private func snapshot(buffer: String, cursor: Int) -> InlineCompletionEditorSnapshot {
        InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/test.css",
            language: "css",
            buffer: buffer,
            cursorPosition: cursor,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .automatic
        )
    }
}

// MARK: - Mocks

@MainActor
private final class CapturedSuggestions: @unchecked Sendable {
    private(set) var lastSuggestion: String?
    private(set) var lastPresentation: InlineSuggestionPresentation?

    func set(_ presentation: InlineSuggestionPresentation?) {
        lastPresentation = presentation
        lastSuggestion = presentation?.suggestionText
    }

    func reset() {
        lastSuggestion = nil
        lastPresentation = nil
    }
}

@MainActor
private final class TestEngineInferenceService: CompletionInferring {
    enum Response {
        case immediate(String)
        case delayed(String, UInt64)
    }

    var responses: [Response] = []

    func infer(for request: InlineCompletionRequest, settings: InlineCompletionSettings) async throws -> InlineCompletionResult? {
        guard !responses.isEmpty else { return nil }
        let response = responses.removeFirst()
        switch response {
        case .immediate(let text):
            return InlineCompletionResult(requestId: request.requestId, suggestionText: text, confidenceScore: 0.8, source: .local, latencyMs: 10)
        case .delayed(let text, let delay):
            try? await Task.sleep(nanoseconds: delay)
            return InlineCompletionResult(requestId: request.requestId, suggestionText: text, confidenceScore: 0.8, source: .local, latencyMs: Double(delay) / 1_000_000)
        }
    }
}

@MainActor
private final class TestEngineRetrievalLayer: CompletionRetrieving {
    func retrieveContext(for snapshot: InlineCompletionEditorSnapshot, request: CompletionContextPayload, settings: InlineCompletionSettings, reduceWorkload: Bool) async -> [String] { [] }
}

@MainActor
private final class EngineTestSettingsStore: InlineCompletionSettingsStore {
    private let multilineEnabled: Bool
    init(multilineEnabled: Bool) { self.multilineEnabled = multilineEnabled; super.init() }

    override func load() -> InlineCompletionSettings {
        InlineCompletionSettings(
            isEnabled: true, debounceMilliseconds: 0, aggressiveness: 0.6,
            maxSuggestionLength: 200, multilineEnabled: multilineEnabled,
            retrievalEnabled: false, routingMode: .localOnly, debugOverlayEnabled: false
        )
    }
}
