import XCTest
@testable import osx_ide

@MainActor
final class InlineCompletionEngineTests: XCTestCase {
    func testLatestRequestWinsWhenEarlierRequestCompletesLater() async {
        let retrieval = TestRetrievalLayer()
        let inference = TestInferenceService()
        inference.responses = [
            .delayed("first", 150_000_000),
            .immediate("second")
        ]

        let engine = InlineCompletionEngine(
            settingsStore: TestInlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: retrieval,
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )

        var received: [String] = []
        engine.registerSuggestionHandler(for: .primary) { presentation in
            if let presentation {
                received.append(presentation.suggestionText)
            }
        }

        let first = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "let ",
            cursorPosition: 4,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )
        let second = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "return ",
            cursorPosition: 7,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )

        engine.requestCompletion(for: first)
        engine.requestCompletion(for: second)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(received.last, "second")
        XCTAssertFalse(received.contains("first"))
    }

    func testDisabledRetrievalIsSkippedByEngine() async {
        let retrieval = CountingRetrievalLayer()
        let inference = TestInferenceService()
        inference.responses = [.immediate("value")]

        let engine = InlineCompletionEngine(
            settingsStore: DisabledRetrievalSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: retrieval,
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )

        let snapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "return ",
            cursorPosition: 7,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )

        engine.requestCompletion(for: snapshot)
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(retrieval.invocationCount, 0)
    }

    func testInvalidateClearsActiveSuggestion() async {
        let retrieval = TestRetrievalLayer()
        let inference = TestInferenceService()
        inference.responses = [.immediate("value")]

        let engine = InlineCompletionEngine(
            settingsStore: TestInlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: retrieval,
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )

        var latest: InlineSuggestionPresentation?
        engine.registerSuggestionHandler(for: .primary) { presentation in
            latest = presentation
        }

        let snapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "return ",
            cursorPosition: 7,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )

        engine.requestCompletion(for: snapshot)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(latest?.suggestionText, "value")

        engine.invalidate(.primary)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(latest)
    }

    func testImmediateRepeatAfterAcceptIsSuppressed() async {
        let retrieval = TestRetrievalLayer()
        let inference = TestInferenceService()
        inference.responses = [
            .immediate("isAdmin: Bool"),
            .immediate("isAdmin: Bool")
        ]

        let engine = InlineCompletionEngine(
            settingsStore: TestInlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: retrieval,
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )

        var latest: InlineSuggestionPresentation?
        engine.registerSuggestionHandler(for: .primary) { presentation in
            latest = presentation
        }

        let firstSnapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/User.swift",
            language: "swift",
            buffer: "struct User {\n    let ",
            cursorPosition: 22,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )

        engine.requestCompletion(for: firstSnapshot)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(latest?.suggestionText, "isAdmin: Bool")

        engine.markAccepted(on: .primary, suggestionText: "isAdmin: Bool")

        let repeatedSnapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/User.swift",
            language: "swift",
            buffer: "struct User {\n    let isAdmin: Bool",
            cursorPosition: 35,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )

        engine.requestCompletion(for: repeatedSnapshot)
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNil(latest)
    }

    func testRepeatAfterAcceptIsSuppressedWhenWhitespaceDiffers() async {
        let retrieval = TestRetrievalLayer()
        let inference = TestInferenceService()
        inference.responses = [
            .immediate("isAdmin: Bool"),
            .immediate("  isAdmin: Bool  ")
        ]

        let engine = InlineCompletionEngine(
            settingsStore: TestInlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: retrieval,
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )

        var latest: InlineSuggestionPresentation?
        engine.registerSuggestionHandler(for: .primary) { presentation in
            latest = presentation
        }

        let firstSnapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/User.swift",
            language: "swift",
            buffer: "struct User {\n    let ",
            cursorPosition: 22,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )

        engine.requestCompletion(for: firstSnapshot)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(latest?.suggestionText, "isAdmin: Bool")

        engine.markAccepted(on: .primary, suggestionText: "isAdmin: Bool")

        let repeatedSnapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/User.swift",
            language: "swift",
            buffer: "struct User {\n    let   isAdmin: Bool  ",
            cursorPosition: 38,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .manual
        )

        engine.requestCompletion(for: repeatedSnapshot)
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNil(latest)
    }

    func testSlowAutomaticSuggestionIsDroppedByLatencyBudget() async {
        let retrieval = TestRetrievalLayer()
        let inference = TestInferenceService()
        inference.responses = [.delayed("slowValue", 2_700_000_000)]

        let engine = InlineCompletionEngine(
            settingsStore: TestInlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: retrieval,
            inferenceService: inference,
            ranker: SuggestionRanker(),
            telemetryService: CompletionTelemetryService()
        )

        var latest: InlineSuggestionPresentation?
        engine.registerSuggestionHandler(for: .primary) { presentation in
            latest = presentation
        }

        let snapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "return ",
            cursorPosition: 7,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .automatic
        )

        engine.requestCompletion(for: snapshot)
        try? await Task.sleep(nanoseconds: 2_900_000_000)

        XCTAssertNil(latest)
    }
}

@MainActor
private final class TestInlineCompletionSettingsStore: InlineCompletionSettingsStore {
    override func load() -> InlineCompletionSettings {
        InlineCompletionSettings(
            isEnabled: true,
            debounceMilliseconds: 0,
            aggressiveness: 0.4,
            maxSuggestionLength: 120,
            multilineEnabled: false,
            retrievalEnabled: false,
            routingMode: .localOnly,
            debugOverlayEnabled: false
        )
    }
}

@MainActor
private final class DisabledRetrievalSettingsStore: InlineCompletionSettingsStore {
    override func load() -> InlineCompletionSettings {
        InlineCompletionSettings(
            isEnabled: true,
            debounceMilliseconds: 0,
            aggressiveness: 0.4,
            maxSuggestionLength: 120,
            multilineEnabled: false,
            retrievalEnabled: false,
            routingMode: .localOnly,
            debugOverlayEnabled: false
        )
    }
}

@MainActor
private final class TestRetrievalLayer: CompletionRetrieving {
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
final class CountingRetrievalLayer: CompletionRetrieving {
    private(set) var invocationCount = 0

    func retrieveContext(
        for snapshot: InlineCompletionEditorSnapshot,
        request: CompletionContextPayload,
        settings: InlineCompletionSettings,
        reduceWorkload: Bool
    ) async -> [String] {
        invocationCount += 1
        return []
    }
}

@MainActor
private final class TestInferenceService: CompletionInferring {
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
