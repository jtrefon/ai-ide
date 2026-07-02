import XCTest
@testable import osx_ide

/// Layer 1: SuggestionRanker — tests that the ranker correctly accepts/rejects
/// single-line and multi-line completions under various configurations.
@MainActor
final class FIMRankerUnitTests: XCTestCase {

    private func makeRequest(
        prefix: String = "",
        suffix: String = "",
        maxLength: Int = 200,
        multiline: Bool
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
            triggerReason: multiline ? .manual : .automatic,
            maxSuggestionLength: maxLength,
            maxTokens: max(10, maxLength / 3),
            allowMultiline: multiline
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

    // MARK: - Single-line (allowMultiline=false)

    func test_singleLine_simpleCSSProperty_isAccepted() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".foo {\n    colo",
            suffix: "\n}",
            multiline: false
        )
        let result = makeResult(requestId: request.requestId, text: "color: #007aff;")

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertNotNil(presentation)
        XCTAssertEqual(presentation?.suggestionText, "color: #007aff;")
    }

    func test_singleLine_multilineInput_isRejected() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".foo {\n    ",
            suffix: "\n}",
            multiline: false
        )
        let result = makeResult(requestId: request.requestId, text: "\n    display: flex;\n    gap: 8px;")

        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func test_singleLine_duplicateSuffix_isRejected() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: "let x = ",
            suffix: "42",
            multiline: false
        )
        let result = makeResult(requestId: request.requestId, text: "42")

        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func test_singleLine_exceedsMaxLength_isRejected() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: "let x = ",
            suffix: "\n",
            maxLength: 5,
            multiline: false
        )
        let result = makeResult(requestId: request.requestId, text: "hello world")

        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func test_singleLine_leadingWhitespace_isTrimmed() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".foo {\n    ",
            suffix: "\n}",
            multiline: false
        )
        let result = makeResult(requestId: request.requestId, text: "  color: red;  ")

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertEqual(presentation?.suggestionText, "color: red;")
    }

    // MARK: - Multi-line (allowMultiline=true)

    func test_multiLine_cssBlock_withNewlines_isAccepted() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".header {\n    ",
            suffix: "\n}",
            multiline: true
        )
        let blockText = "\n    display: flex;\n    flex-direction: column;\n    align-items: center;"
        let result = makeResult(requestId: request.requestId, text: blockText)

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertNotNil(presentation)
        XCTAssertTrue(presentation!.suggestionText.contains("display: flex"))
        XCTAssertTrue(presentation!.suggestionText.contains("flex-direction"))
        XCTAssertTrue(presentation!.suggestionText.contains("align-items"))
    }

    func test_multiLine_trailingNewlines_areTrimmed() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".header {\n    ",
            suffix: "\n}",
            multiline: true
        )
        let result = makeResult(requestId: request.requestId, text: "  display: block;\n  \n  \n")

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertEqual(presentation?.suggestionText, "display: block;")
    }

    func test_multiLine_respectsIndentation() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".foo {\n    ",
            suffix: "\n}",
            multiline: true
        )
        let result = makeResult(requestId: request.requestId, text: "\n    color: red;\n    margin: 0;")

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertNotNil(presentation)
        XCTAssertTrue(presentation!.suggestionText.contains("color: red"))
        XCTAssertTrue(presentation!.suggestionText.contains("margin: 0"))
    }

    func test_multiLine_wrongIndentation_isRejected() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".foo {\n    ",
            suffix: "\n}",
            multiline: true
        )
        let result = makeResult(requestId: request.requestId, text: "\n    color: red;\n\tmargin: 0;")

        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func test_multiLine_sameContentAfterAccept_isSuppressedByEngine() {
        let ranker = SuggestionRanker()
        let request = makeRequest(
            prefix: ".foo {\n    ",
            suffix: "\n}",
            multiline: true
        )
        let blockText = "\n    display: flex;\n    gap: 8px;"
        let result = makeResult(requestId: request.requestId, text: blockText)

        // The ranker accepts it — suppression is handled by the engine's
        // repeated-after-accept check, not the ranker itself
        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertNotNil(presentation)
    }

    // MARK: - Aggressiveness

    func test_aggressiveness_high_acceptsLowConfidence() {
        let ranker = SuggestionRanker()
        let request = makeRequest(multiline: false)
        let result = makeResult(requestId: request.requestId, text: "color: red;", confidence: 0.1)

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.9)
        XCTAssertNotNil(presentation)
        XCTAssertEqual(presentation?.confidenceScore, 0.9)
    }

    func test_aggressiveness_low_usesConfidence() {
        let ranker = SuggestionRanker()
        let request = makeRequest(multiline: false)
        let result = makeResult(requestId: request.requestId, text: "color: red;", confidence: 0.7)

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.3)
        XCTAssertNotNil(presentation)
        XCTAssertEqual(presentation?.confidenceScore, 0.7)
    }
}
