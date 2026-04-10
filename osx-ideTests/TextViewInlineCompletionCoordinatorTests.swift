import XCTest
import SwiftUI
import AppKit
@testable import osx_ide

@MainActor
final class TextViewInlineCompletionCoordinatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        IndentationStyle.setCurrent(.tabs)
    }

    func testEscapeDismissesInlineSuggestion() {
        let sourceText = "return "
        let parent = makeParent(text: "return ")
        let coordinator = TextViewRepresentable.Coordinator(parent)
        let textView = CodeEditorTextView()
        textView.string = sourceText
        textView.setSelectedRange(NSRange(location: sourceText.count, length: 0))
        coordinator.attach(textView: textView)

        textView.updateGhostSuggestion(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "value",
                source: .local,
                confidenceScore: 0.8,
                latencyMs: 5
            )
        )

        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertFalse(textView.hasInlineSuggestion)
    }

    func testTypingClearsInlineSuggestionBeforeEdit() {
        let sourceText = "return "
        let parent = makeParent(text: "return ")
        let coordinator = TextViewRepresentable.Coordinator(parent)
        let textView = CodeEditorTextView()
        textView.string = sourceText
        textView.setSelectedRange(NSRange(location: sourceText.count, length: 0))
        coordinator.attach(textView: textView)

        textView.updateGhostSuggestion(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "value",
                source: .local,
                confidenceScore: 0.8,
                latencyMs: 5
            )
        )

        _ = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: sourceText.count, length: 0),
            replacementString: "x"
        )

        XCTAssertFalse(textView.hasInlineSuggestion)
    }

    func testFileSwitchClearsInlineSuggestion() {
        let sourceText = "return "
        let parent = makeParent(text: "return ")
        let coordinator = TextViewRepresentable.Coordinator(parent)
        let textView = CodeEditorTextView()
        textView.string = sourceText
        textView.setSelectedRange(NSRange(location: sourceText.count, length: 0))
        coordinator.attach(textView: textView)

        textView.updateGhostSuggestion(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "value",
                source: .local,
                confidenceScore: 0.8,
                latencyMs: 5
            )
        )

        coordinator.handleFileSwitch(textView: textView)

        XCTAssertFalse(textView.hasInlineSuggestion)
    }

    func testAutoPairWrapsSelectionWithoutMutatingUnexpectedly() {
        let sourceText = "value"
        let parent = makeParent(text: sourceText)
        let coordinator = TextViewRepresentable.Coordinator(parent)
        let textView = CodeEditorTextView()
        textView.string = sourceText
        textView.setSelectedRange(NSRange(location: 0, length: sourceText.count))
        coordinator.attach(textView: textView)

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: sourceText.count),
            replacementString: "("
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textView.string, "(value)")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: sourceText.count + 1, length: 0))
    }

    func testContextualNewlineExpandsBraceBlock() {
        let sourceText = "{}"
        let parent = makeParent(text: sourceText)
        let coordinator = TextViewRepresentable.Coordinator(parent)
        let textView = CodeEditorTextView()
        textView.string = sourceText
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        coordinator.attach(textView: textView)

        let handled = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 1, length: 0),
            replacementString: "\n"
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(textView.string, "{\n\t\n}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testInsertNewlineCommandExpandsBraceBlock() {
        let sourceText = "{}"
        let parent = makeParent(text: sourceText)
        let coordinator = TextViewRepresentable.Coordinator(parent)
        let textView = CodeEditorTextView()
        textView.string = sourceText
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        coordinator.attach(textView: textView)

        let handled = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(textView.string, "{\n\t\n}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    private func makeParent(text: String) -> TextViewRepresentable {
        let storage = TextStorageBox(text)
        return TextViewRepresentable(
            paneID: .primary,
            text: Binding(get: { storage.text }, set: { storage.text = $0 }),
            filePath: "/tmp/Test.swift",
            language: "swift",
            selectedRange: .constant(nil),
            selectionContext: CodeSelectionContext(),
            inlineCompletionEngine: InlineCompletionEngine(
                settingsStore: InlineCompletionSettingsStore(),
                triggerPolicy: CompletionTriggerPolicy(),
                contextAssembler: CompletionContextAssembler(),
                retrievalLayer: CompletionRetrievalLayer(projectRootProvider: { nil }, codebaseIndexProvider: { nil }),
                inferenceService: CompletionInferenceService(
                    provider: AIServiceInlineCompletionProvider(
                        aiServiceProvider: { nil },
                        offlineModeChecker: TestTextViewOfflineModeChecker()
                    )
                ),
                ranker: SuggestionRanker()
            ),
            showLineNumbers: false,
            wordWrap: false,
            fontSize: 12,
            fontFamily: AppConstants.Editor.defaultFontFamily
        )
    }
}

@MainActor
private final class TestTextViewOfflineModeChecker: OfflineModeChecking {
    func isOfflineModeEnabled() async -> Bool {
        false
    }
}

@MainActor
private final class TextStorageBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
