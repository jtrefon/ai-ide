import SwiftUI
import AppKit

final class TextStorageDelegateProxy: NSObject, NSTextStorageDelegate {
    weak var coordinator: TextViewRepresentable.Coordinator?

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range _: NSRange,
        changeInLength _: Int
    ) {
        if !editedMask.contains(.editedCharacters) { return }
        let text = textStorage.string
        Task { @MainActor [weak coordinator] in
            coordinator?.handleDidProcessEditing(text: text)
        }
    }
}

extension TextViewRepresentable {
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: TextViewRepresentable
        var isProgrammaticUpdate = false
        var isProgrammaticSelectionUpdate = false
        fileprivate var currentHighlightTask: Task<Void, Never>?
        fileprivate var pendingHighlightTask: Task<Void, Never>?
        fileprivate weak var attachedTextView: NSTextView?
        let textStorageDelegateProxy: TextStorageDelegateProxy

        init(_ parent: TextViewRepresentable) {
            self.parent = parent
            self.textStorageDelegateProxy = TextStorageDelegateProxy()
            super.init()
            self.textStorageDelegateProxy.coordinator = self
        }

        func attach(textView: NSTextView) {
            self.attachedTextView = textView
        }

        // MARK: - Real-time editor behaviors

        @MainActor
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if isProgrammaticUpdate { return true }
            guard let replacementString else { return true }

            // Only apply behaviors for simple insertions (typing). Let multi-char replacements go through.
            if replacementString.count != 1 { return true }

            let character = replacementString
            let openToClose: [String: String] = [
                "(": ")",
                "[": "]",
                "{": "}",
                "\"": "\"",
                "'": "'"
            ]

            // Smart newline between braces: `{|}` -> `{
            //   |
            // }`
            if character == "\n" || character == "\r" {
                return handleContextualNewline(in: textView)
            }

            // Auto-close pairs
            if let close = openToClose[character] {
                return handleAutoPair(open: character, close: close, in: textView, affectedCharRange: affectedCharRange)
            }

            // Skip over an existing closing token
            let closingTokens: Set<String> = [")", "]", "}", "\"", "'"]
            if closingTokens.contains(character) {
                return handleSkipOverClosingIfPresent(character, in: textView)
            }

            return true
        }

        @MainActor
        private func handleAutoPair(
            open: String,
            close: String,
            in textView: NSTextView,
            affectedCharRange: NSRange
        ) -> Bool {
            // If text is selected, wrap it.
            let selected = textView.selectedRange
            if selected.length > 0, let textStorage = textView.textStorage {
                isProgrammaticUpdate = true
                defer { isProgrammaticUpdate = false }

                let selectedText = (textView.string as NSString).substring(with: selected)
                let replacement = open + selectedText + close
                textStorage.replaceCharacters(in: selected, with: replacement)
                textView.setSelectedRange(NSRange(location: selected.location + 1 + selected.length, length: 0))
                finalizeInterceptedEdit(in: textView)
                return false
            }

            // If next character is already the closing token, don't duplicate for symmetric quotes.
            if (open == "\"" || open == "'") && nextCharacter(in: textView) == close {
                return true
            }

            guard let textStorage = textView.textStorage else { return true }
            isProgrammaticUpdate = true
            defer { isProgrammaticUpdate = false }

            let insertionRange = NSRange(location: affectedCharRange.location, length: 0)
            textStorage.replaceCharacters(in: insertionRange, with: open + close)
            textView.setSelectedRange(NSRange(location: insertionRange.location + 1, length: 0))
            finalizeInterceptedEdit(in: textView)
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
                finalizeInterceptedEdit(in: textView)
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

            // Portion of the current line before the cursor
            let prefixLength = max(0, min(safeCursor - currentLineRange.location, currentLineRange.length))
            let linePrefix = (currentLine as NSString).substring(to: prefixLength)
            let trimmedPrefix = linePrefix.trimmingCharacters(in: .whitespacesAndNewlines)

            // If the user is between braces, expand to a two-line block.
            if previousCharacter(in: textView) == "{" && nextCharacter(in: textView) == "}" {
                let innerIndent = baseIndent + indentUnit
                let insertion = "\n" + innerIndent + "\n" + baseIndent

                isProgrammaticUpdate = true
                defer { isProgrammaticUpdate = false }

                textStorage.replaceCharacters(in: NSRange(location: safeCursor, length: 0), with: insertion)
                let newCursor = safeCursor + 1 + (innerIndent as NSString).length
                textView.setSelectedRange(NSRange(location: newCursor, length: 0))
                finalizeInterceptedEdit(in: textView)
                return false
            }

            // Normal newline indentation:
            // - Add one indent after lines ending with '{'
            // - Reduce one indent if the next non-whitespace token is '}'
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
            finalizeInterceptedEdit(in: textView)
            return false
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
            // Remove up to tabWidth spaces as a fallback.
            let tabWidth = AppConstants.Editor.tabWidth
            let spacesToRemove = min(tabWidth, baseIndent.count)
            let trimmed = String(baseIndent.dropLast(spacesToRemove))
            return trimmed
        }

        @MainActor
        private func finalizeInterceptedEdit(in textView: NSTextView) {
            // Our intercepted edits bypass `textDidChange` (because we guard with `isProgrammaticUpdate`).
            // If we don't sync state here, SwiftUI can later overwrite the text view contents,
            // and highlighting won't be scheduled.
            self.parent.text = textView.string
            self.parent.selectedRange = textView.selectedRange
            updateSelectionContext(from: textView)

            scheduleHighlight(
                for: textView.string,
                in: textView,
                language: parent.language,
                font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            )
        }

        @MainActor
        private func currentLineIndent(in textView: NSTextView) -> String {
            let nsString = textView.string as NSString
            let cursor = textView.selectedRange.location
            let safeCursor = max(0, min(cursor, nsString.length))

            // Get the range of the current line using NSString APIs (robust and index-safe)
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
