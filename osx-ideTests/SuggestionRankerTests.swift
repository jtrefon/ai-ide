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
}
