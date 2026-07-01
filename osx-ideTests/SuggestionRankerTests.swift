import XCTest
@testable import osx_ide

@MainActor
final class SuggestionRankerTests: XCTestCase {
    func testRankerRejectsDuplicateSuffix() {
        let ranker = SuggestionRanker()
        let request = InlineCompletionRequest(
            requestId: UUID(),
            filePath: nil,
            language: "swift",
            prefix: "let value = ",
            suffix: "42\n",
            cursorPosition: 12,
            scopeSummary: nil,
            symbols: [],
            retrievalContext: [],
            triggerReason: .automatic,
            maxSuggestionLength: 32,
            maxTokens: 11,
            allowMultiline: false
        )
        let result = InlineCompletionResult(
            requestId: request.requestId,
            suggestionText: "42",
            confidenceScore: 0.8,
            source: .local,
            latencyMs: 10
        )

        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func testRankerReturnsTrimmedSingleLinePresentation() {
        let ranker = SuggestionRanker()
        let request = InlineCompletionRequest(
            requestId: UUID(),
            filePath: nil,
            language: "swift",
            prefix: "return ",
            suffix: "\n",
            cursorPosition: 7,
            scopeSummary: nil,
            symbols: [],
            retrievalContext: [],
            triggerReason: .automatic,
            maxSuggestionLength: 40,
            maxTokens: 14,
            allowMultiline: false
        )
        let result = InlineCompletionResult(
            requestId: request.requestId,
            suggestionText: "```swift\nvalue\n```",
            confidenceScore: 0.7,
            source: .local,
            latencyMs: 12
        )

        let presentation = ranker.rank(result, for: request, aggressiveness: 0.5)
        XCTAssertEqual(presentation?.suggestionText, "value")
    }

    func testRankerRejectsMultilineGhostSuggestion() {
        let ranker = SuggestionRanker()
        let request = InlineCompletionRequest(
            requestId: UUID(),
            filePath: nil,
            language: "swift",
            prefix: "if condition {",
            suffix: "\n}",
            cursorPosition: 14,
            scopeSummary: nil,
            symbols: [],
            retrievalContext: [],
            triggerReason: .automatic,
            maxSuggestionLength: 80,
            maxTokens: 28,
            allowMultiline: false
        )
        let result = InlineCompletionResult(
            requestId: request.requestId,
            suggestionText: "\n\treturn value",
            confidenceScore: 0.9,
            source: .local,
            latencyMs: 20
        )

        XCTAssertNil(ranker.rank(result, for: request, aggressiveness: 0.5))
    }

    func testRankerAllowsMultilineSuggestionWhenEnabled() {
        let ranker = SuggestionRanker()
        let request = InlineCompletionRequest(
            requestId: UUID(),
            filePath: nil,
            language: "swift",
            prefix: "if condition {\n    ",
            suffix: "\n}",
            cursorPosition: 19,
            scopeSummary: nil,
            symbols: [],
            retrievalContext: [],
            triggerReason: .manual,
            maxSuggestionLength: 80,
            maxTokens: 28,
            allowMultiline: true
        )
        let result = InlineCompletionResult(
            requestId: request.requestId,
            suggestionText: "\n    return value\n    print(value)",
            confidenceScore: 0.9,
            source: .local,
            latencyMs: 20
        )

        XCTAssertEqual(
            ranker.rank(result, for: request, aggressiveness: 0.5)?.suggestionText,
            "return value\n    print(value)"
        )
    }
}
