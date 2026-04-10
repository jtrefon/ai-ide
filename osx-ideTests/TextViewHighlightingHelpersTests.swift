import XCTest
import SwiftUI
import AppKit
@testable import osx_ide

@MainActor
final class TextViewHighlightingHelpersTests: XCTestCase {
    private var inlineCompletionEngine: InlineCompletionEngine {
        InlineCompletionEngine(
            settingsStore: InlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: CompletionRetrievalLayer(
                projectRootProvider: { nil },
                codebaseIndexProvider: { nil }
            ),
            inferenceService: CompletionInferenceService(
                provider: AIServiceInlineCompletionProvider(aiServiceProvider: { nil })
            ),
            ranker: SuggestionRanker()
        )
    }

    func testApplyHighlightAttributesCopiesForegroundColors() {
        var text = "abc"
        let parent = TextViewRepresentable(
            paneID: .primary,
            text: Binding(get: { text }, set: { text = $0 }),
            filePath: nil,
            language: "swift",
            selectedRange: .constant(nil),
            selectionContext: CodeSelectionContext(),
            inlineCompletionEngine: inlineCompletionEngine,
            showLineNumbers: false,
            wordWrap: false,
            fontSize: 12,
            fontFamily: AppConstants.Editor.defaultFontFamily
        )
        let coordinator = TextViewRepresentable.Coordinator(parent)

        let textView = NSTextView()
        textView.string = text
        guard let textStorage = textView.textStorage else {
            XCTFail("Expected NSTextView to have a textStorage")
            return
        }

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 1, length: 1))

        coordinator.applyHighlightAttributes(textStorage: textStorage, attributedString: attributed, font: font)

        let c0 = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let c1 = textStorage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor

        XCTAssertEqual(c1, NSColor.systemRed)
        XCTAssertNotNil(c0)
    }

    func testBuildHighlightDiagnosticsNormalizesLanguagePrefix() {
        let attributed = NSAttributedString(string: "x", attributes: [.foregroundColor: NSColor.systemBlue])
        let diagnostics = TextViewRepresentable.Coordinator.buildHighlightDiagnostics(from: attributed, language: ".js")
        XCTAssertTrue(diagnostics.contains("lang=javascript"))
    }
}
