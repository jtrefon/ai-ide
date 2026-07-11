import XCTest
@testable import osx_ide

@MainActor
final class GhostCodeRankerTests: XCTestCase {
    private func makeRequest(
        prefix: String = "",
        suffix: String = "",
        maxLength: Int = 400
    ) -> InlineCompletionRequest {
        InlineCompletionRequest(
            requestId: UUID(),
            filePath: nil,
            language: "css",
            prefix: prefix,
            suffix: suffix,
            cursorPosition: prefix.count,
            scopeSummary: nil,
            symbols: [],
            retrievalContext: [],
            triggerReason: .manual,
            maxSuggestionLength: maxLength,
            maxTokens: max(10, maxLength / 3),
            allowMultiline: true
        )
    }

    private func makeResult(
        requestId: UUID,
        text: String,
        confidence: Double = 0.8
    ) -> InlineCompletionResult {
        InlineCompletionResult(
            requestId: requestId,
            suggestionText: text,
            confidenceScore: confidence,
            source: .local,
            latencyMs: 10
        )
    }

    // MARK: - Multi-line acceptance

    func test_multiLine_cssBlock_isAccepted() {
        let ranker = GhostCodeRanker()
        let request = makeRequest(prefix: ".header {\n    ", suffix: "\n}")
        let blockText = "\n    display: flex;\n    flex-direction: column;\n    align-items: center;"
        let result = makeResult(requestId: request.requestId, text: blockText)

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertNotNil(presentation)
        XCTAssertTrue(presentation!.suggestionText.contains("display: flex"))
        XCTAssertTrue(presentation!.suggestionText.contains("flex-direction"))
        XCTAssertTrue(presentation!.suggestionText.contains("align-items"))
    }

    func test_multiLine_respectsIndentation() {
        let ranker = GhostCodeRanker()
        let request = makeRequest(prefix: ".foo {\n    ", suffix: "\n}")
        let result = makeResult(requestId: request.requestId, text: "\n    color: red;\n    margin: 0;")

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertNotNil(presentation)
        XCTAssertTrue(presentation!.suggestionText.contains("color: red"))
        XCTAssertTrue(presentation!.suggestionText.contains("margin: 0"))
    }

    func test_multiLine_wrongIndentation_isRejected() {
        let ranker = GhostCodeRanker()
        let request = makeRequest(prefix: ".foo {\n    ", suffix: "\n}")
        let result = makeResult(requestId: request.requestId, text: "\n    color: red;\n\tmargin: 0;")

        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func test_empty_isRejected() {
        let ranker = GhostCodeRanker()
        let request = makeRequest()
        let result = makeResult(requestId: request.requestId, text: "")
        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    // MARK: - Self-repetition

    func test_selfRepetition_multiline_isRejected() {
        let ranker = GhostCodeRanker()
        let request = makeRequest(prefix: "let x = ", suffix: "\n")
        let repetitive = "foo bar foo bar foo bar foo bar"
        let result = makeResult(requestId: request.requestId, text: repetitive)
        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func test_nonRepetition_isAccepted() {
        let ranker = GhostCodeRanker()
        let request = makeRequest(prefix: "let x = ", suffix: "\n")
        let result = makeResult(requestId: request.requestId, text: "42")
        XCTAssertNotNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    // MARK: - Code fence stripping

    func test_codeFence_isStripped() {
        let ranker = GhostCodeRanker()
        let request = makeRequest()
        let result = makeResult(requestId: request.requestId, text: "```swift\nvalue\n```")

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertEqual(presentation?.suggestionText, "value")
    }

    // MARK: - Aggressiveness

    func test_aggressiveness_high_acceptsLowConfidence() {
        let ranker = GhostCodeRanker()
        let request = makeRequest()
        let result = makeResult(requestId: request.requestId, text: "color: red;", confidence: 0.1)

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.9)
        XCTAssertNotNil(presentation)
        XCTAssertEqual(presentation?.confidenceScore, 0.9)
    }
}
