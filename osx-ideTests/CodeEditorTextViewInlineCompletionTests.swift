import XCTest
import AppKit
@testable import osx_ide

@MainActor
final class CodeEditorTextViewInlineCompletionTests: XCTestCase {
    func testGhostSuggestionDoesNotMutateBufferUntilAccepted() {
        let textView = CodeEditorTextView()
        textView.string = "let answer = "
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.updateGhostSuggestion(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "42",
                source: .local,
                confidenceScore: 0.9,
                latencyMs: 8
            )
        )

        XCTAssertEqual(textView.string, "let answer = ")
        XCTAssertTrue(textView.hasInlineSuggestion)
    }

    func testAcceptSuggestionInsertsTextAndClearsPresentation() {
        let textView = CodeEditorTextView()
        textView.string = "let answer = "
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.updateGhostSuggestion(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "42",
                source: .local,
                confidenceScore: 0.9,
                latencyMs: 8
            )
        )

        XCTAssertTrue(textView.acceptInlineSuggestion())
        XCTAssertEqual(textView.string, "let answer = 42")
        XCTAssertFalse(textView.hasInlineSuggestion)
    }

    func testAcceptMultilineSuggestionPreservesFormatting() {
        let textView = CodeEditorTextView()
        textView.string = "if condition {\n    "
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.updateGhostSuggestion(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "return value\n    print(value)",
                source: .local,
                confidenceScore: 0.9,
                latencyMs: 8
            )
        )

        XCTAssertTrue(textView.acceptInlineSuggestion())
        XCTAssertEqual(textView.string, "if condition {\n    return value\n    print(value)")
        XCTAssertFalse(textView.hasInlineSuggestion)
    }
}
