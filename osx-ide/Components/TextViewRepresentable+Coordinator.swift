import SwiftUI
import AppKit

extension TextViewRepresentable {
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: TextViewRepresentable
        var currentLanguageIdentifier: String
        var isProgrammaticUpdate = false
        var isProgrammaticSelectionUpdate = false
        var currentFilePath: String?
        weak var attachedTextView: NSTextView?
        let signalBridge: EditorSignalBridge?

        init(_ parent: TextViewRepresentable) {
            self.parent = parent
            self.currentLanguageIdentifier = parent.language
            self.currentFilePath = parent.filePath
            self.signalBridge = EditorSignalBridge(
                paneID: parent.paneID,
                engine: parent.inlineCompletionEngine
            )
            super.init()
        }

        func attach(textView: NSTextView) {
            self.attachedTextView = textView
            configureInlineCompletionHandlers()
        }

        deinit {
            let inlineCompletionEngine = parent.inlineCompletionEngine
            let paneID = parent.paneID
            Task { @MainActor in
                inlineCompletionEngine.unregisterSuggestionHandler(for: paneID)
                inlineCompletionEngine.unregisterManualTriggerHandler(for: paneID)
                InlineCompletionDebugStore.shared.update(paneID: paneID, presentation: nil)
            }
        }

        // MARK: - Real-time editor behaviors

        @MainActor
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if isProgrammaticUpdate { return true }

            if let codeEditorTextView = textView as? CodeEditorTextView,
               codeEditorTextView.hasInlineSuggestion,
               replacementString != nil {
                codeEditorTextView.clearInlineSuggestion()
                invalidateInlineCompletion()
            }

            guard let replacementString else { return true }

            if replacementString.count != 1 { return true }

            let character = replacementString
            let openToClose: [String: String] = [
                "(": ")",
                "[": "]",
                "{": "}",
                "\"": "\"",
                "'": "'"
            ]

            if character == "\n" || character == "\r" {
                return handleContextualNewline(in: textView)
            }

            if let close = openToClose[character] {
                return handleAutoPair(open: character, close: close, in: textView, affectedCharRange: affectedCharRange)
            }

            let closingTokens: Set<String> = [")", "]", "}", "\"", "'"]
            if closingTokens.contains(character) {
                return handleSkipOverClosingIfPresent(character, in: textView)
            }

            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let codeEditorTextView = textView as? CodeEditorTextView else {
                return false
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shouldAllowDefault = handleContextualNewline(in: textView)
                return !shouldAllowDefault
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)), codeEditorTextView.hasInlineSuggestion {
                let acceptedSuggestion = codeEditorTextView.inlineSuggestionText
                let accepted = codeEditorTextView.acceptInlineSuggestion()
                if accepted {
                    parent.inlineCompletionEngine.markAccepted(
                        on: parent.paneID,
                        suggestionText: acceptedSuggestion
                    )
                    parent.text = textView.string
                    parent.selectedRange = textView.selectedRange
                    updateSelectionContext(from: textView)
                }
                return accepted
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)), codeEditorTextView.hasInlineSuggestion {
                codeEditorTextView.clearInlineSuggestion()
                parent.inlineCompletionEngine.markDismissed()
                invalidateInlineCompletion()
                return true
            }

            return false
        }

        @MainActor
        private func handleAutoPair(
            open: String,
            close: String,
            in textView: NSTextView,
            affectedCharRange: NSRange
        ) -> Bool {
            let selected = textView.selectedRange
            if selected.length > 0, let textStorage = textView.textStorage {
                isProgrammaticUpdate = true
                defer { isProgrammaticUpdate = false }

                let selectedText = (textView.string as NSString).substring(with: selected)
                let replacement = open + selectedText + close
                textStorage.replaceCharacters(in: selected, with: replacement)
                textView.setSelectedRange(NSRange(location: selected.location + 1 + selected.length, length: 0))
                didModifyText(in: textView)
                return false
            }

            if (open == "\"" || open == "'") && nextCharacter(in: textView) == close {
                return true
            }

            guard let textStorage = textView.textStorage else { return true }
            isProgrammaticUpdate = true
            defer { isProgrammaticUpdate = false }

            let insertionRange = NSRange(location: affectedCharRange.location, length: 0)
            textStorage.replaceCharacters(in: insertionRange, with: open + close)
            textView.setSelectedRange(NSRange(location: insertionRange.location + 1, length: 0))
            didModifyText(in: textView)
            return false
        }

        @MainActor
        private func handleSkipOverClosingIfPresent(_ closingToken: String, in textView: NSTextView) -> Bool {
            let sel = textView.selectedRange
            if sel.length != 0 { return true }

            if nextCharacter(in: textView) == closingToken {
                isProgrammaticSelectionUpdate = true
                defer { isProgrammaticSelectionUpdate = false }
                textView.setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                didModifyText(in: textView)
                return false
            }

            return true
        }

        @MainActor
        private func handleContextualNewline(in textView: NSTextView) -> Bool {
            let sel = textView.selectedRange
            if sel.length != 0 { return true }

            guard let textStorage = textView.textStorage else { return true }

            let nsString = textView.string as NSString
            let cursor = sel.location
            let safeCursor = max(0, min(cursor, nsString.length))

            let indentUnit = IndentationStyle.current().indentUnit(tabWidth: AppConstants.Editor.tabWidth)
            let currentLineRange = nsString.lineRange(for: NSRange(location: safeCursor, length: 0))
            let currentLine = nsString.substring(with: currentLineRange)
            let baseIndent = leadingWhitespace(of: currentLine)

            let prefixLength = max(0, min(safeCursor - currentLineRange.location, currentLineRange.length))
            let linePrefix = (currentLine as NSString).substring(to: prefixLength)
            let trimmedPrefix = linePrefix.trimmingCharacters(in: .whitespacesAndNewlines)

            if previousCharacter(in: textView) == "{" && nextCharacter(in: textView) == "}" {
                let innerIndent = baseIndent + indentUnit
                let insertion = "\n" + innerIndent + "\n" + baseIndent

                isProgrammaticUpdate = true
                defer { isProgrammaticUpdate = false }

                textStorage.replaceCharacters(in: NSRange(location: safeCursor, length: 0), with: insertion)
                let newCursor = safeCursor + 1 + (innerIndent as NSString).length
                textView.setSelectedRange(NSRange(location: newCursor, length: 0))
                didModifyText(in: textView)
                return false
            }

            var targetIndent = baseIndent
            if trimmedPrefix.hasSuffix("{") {
                targetIndent = baseIndent + indentUnit
            } else if nextNonWhitespaceCharacter(in: nsString, from: safeCursor) == "}" {
                targetIndent = dropOneIndent(from: baseIndent, indentUnit: indentUnit)
            }

            let insertion = "\n" + targetIndent

            isProgrammaticUpdate = true
            defer { isProgrammaticUpdate = false }

            textStorage.replaceCharacters(in: NSRange(location: safeCursor, length: 0), with: insertion)
            let newCursor = safeCursor + 1 + (targetIndent as NSString).length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            didModifyText(in: textView)
            return false
        }

        @MainActor
        private func didModifyText(in textView: NSTextView) {
            self.parent.text = textView.string
            self.parent.selectedRange = textView.selectedRange
            updateSelectionContext(from: textView)
        }

        private func nextNonWhitespaceCharacter(in nsString: NSString, from index: Int) -> String? {
            if index < 0 || index >= nsString.length { return nil }
            var scanIndex = index
            while scanIndex < nsString.length {
                let character = nsString.substring(with: NSRange(location: scanIndex, length: 1))
                if character != " " && character != "\t" && character != "\n" && character != "\r" {
                    return character
                }
                scanIndex += 1
            }
            return nil
        }

        private func dropOneIndent(from baseIndent: String, indentUnit: String) -> String {
            if baseIndent.hasSuffix(indentUnit) {
                return String(baseIndent.dropLast((indentUnit as NSString).length))
            }
            if baseIndent.hasSuffix("\t") {
                return String(baseIndent.dropLast(1))
            }
            let tabWidth = AppConstants.Editor.tabWidth
            let spacesToRemove = min(tabWidth, baseIndent.count)
            let trimmed = String(baseIndent.dropLast(spacesToRemove))
            return trimmed
        }

        @MainActor
        private func currentLineIndent(in textView: NSTextView) -> String {
            let nsString = textView.string as NSString
            let cursor = textView.selectedRange.location
            let safeCursor = max(0, min(cursor, nsString.length))

            let lineRange = nsString.lineRange(for: NSRange(location: safeCursor, length: 0))
            if lineRange.location == NSNotFound || lineRange.length == 0 { return "" }

            let line = nsString.substring(with: lineRange)
            return leadingWhitespace(of: line)
        }

        private func leadingWhitespace(of text: String) -> String {
            var result = ""
            for character in text {
                if character == " " || character == "\t" {
                    result.append(character)
                } else {
                    break
                }
            }
            return result
        }

        @MainActor
        private func previousCharacter(in textView: NSTextView) -> String? {
            let nsString = textView.string as NSString
            let pos = textView.selectedRange.location
            if pos <= 0 || pos > nsString.length { return nil }
            return nsString.substring(with: NSRange(location: pos - 1, length: 1))
        }

        @MainActor
        private func nextCharacter(in textView: NSTextView) -> String? {
            let nsString = textView.string as NSString
            let pos = textView.selectedRange.location
            if pos < 0 || pos >= nsString.length { return nil }
            return nsString.substring(with: NSRange(location: pos, length: 1))
        }
    }
}
