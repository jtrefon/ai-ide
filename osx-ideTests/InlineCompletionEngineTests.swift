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
            triggerReason: .manual
        )
        let second = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Test.swift",
            language: "swift",
            buffer: "return ",
            cursorPosition: 7,
            selectionLength: 0,
            triggerReason: .manual
        )

        engine.requestCompletion(for: first)
        engine.requestCompletion(for: second)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(received.last, "second")
        XCTAssertFalse(received.contains("first"))
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
                latencyMs: 100
            )
        }
    }
}
