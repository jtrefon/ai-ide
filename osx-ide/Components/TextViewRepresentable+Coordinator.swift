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
        private var currentHighlightTask: Task<Void, Never>?
        private var pendingHighlightTask: Task<Void, Never>?
        private weak var attachedTextView: NSTextView?
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

            let ch = replacementString
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
            if ch == "\n" || ch == "\r" {
                return handleContextualNewline(in: textView)
            }

            // Auto-close pairs
            if let close = openToClose[ch] {
                return handleAutoPair(open: ch, close: close, in: textView, affectedCharRange: affectedCharRange)
            }

            // Skip over an existing closing token
            let closingTokens: Set<String> = [")", "]", "}", "\"", "'"]
            if closingTokens.contains(ch) {
                return handleSkipOverClosingIfPresent(ch, in: textView)
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
        private func handleSkipOverClosingIfPresent(_ ch: String, in textView: NSTextView) -> Bool {
            let sel = textView.selectedRange
            if sel.length != 0 { return true }

            if nextCharacter(in: textView) == ch {
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

            let ns = textView.string as NSString
            let cursor = sel.location
            let safeCursor = max(0, min(cursor, ns.length))

            let indentUnit = IndentationStyle.current().indentUnit(tabWidth: AppConstants.Editor.tabWidth)
            let currentLineRange = ns.lineRange(for: NSRange(location: safeCursor, length: 0))
            let currentLine = ns.substring(with: currentLineRange)
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
            } else if nextNonWhitespaceCharacter(in: ns, from: safeCursor) == "}" {
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

        private func nextNonWhitespaceCharacter(in ns: NSString, from index: Int) -> String? {
            if index < 0 || index >= ns.length { return nil }
            var i = index
            while i < ns.length {
                let ch = ns.substring(with: NSRange(location: i, length: 1))
                if ch != " " && ch != "\t" && ch != "\n" && ch != "\r" {
                    return ch
                }
                i += 1
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
            let ns = textView.string as NSString
            let cursor = textView.selectedRange.location
            let safeCursor = max(0, min(cursor, ns.length))

            // Get the range of the current line using NSString APIs (robust and index-safe)
            let lineRange = ns.lineRange(for: NSRange(location: safeCursor, length: 0))
            if lineRange.location == NSNotFound || lineRange.length == 0 { return "" }

            let line = ns.substring(with: lineRange)
            return leadingWhitespace(of: line)
        }

        private func leadingWhitespace(of s: String) -> String {
            var result = ""
            for ch in s {
                if ch == " " || ch == "\t" {
                    result.append(ch)
                } else {
                    break
                }
            }
            return result
        }

        @MainActor
        private func previousCharacter(in textView: NSTextView) -> String? {
            let ns = textView.string as NSString
            let pos = textView.selectedRange.location
            if pos <= 0 || pos > ns.length { return nil }
            return ns.substring(with: NSRange(location: pos - 1, length: 1))
        }

        @MainActor
        private func nextCharacter(in textView: NSTextView) -> String? {
            let ns = textView.string as NSString
            let pos = textView.selectedRange.location
            if pos < 0 || pos >= ns.length { return nil }
            return ns.substring(with: NSRange(location: pos, length: 1))
        }

        @MainActor
        func performAsyncHighlight(for text: String, in textView: NSTextView, language: String, font: NSFont) {
            currentHighlightTask?.cancel()

            let syntaxHighlighter = SyntaxHighlighter.shared

            // Store the current selection before update
            let selectedRange = textView.selectedRange
            let typingAttributes = textView.typingAttributes

            // Task inherits @MainActor from Coordinator
            currentHighlightTask = Task {
                let attributedString = syntaxHighlighter.highlight(text, language: language, font: font)

                if Task.isCancelled { return }

                self.isProgrammaticUpdate = true

                // Do NOT replace the entire attributed string (can conflict with AppKit edits on Enter).
                // Instead, apply highlighting in-place by updating attributes only.
                if let textStorage = textView.textStorage {
                    applyHighlightAttributes(textStorage: textStorage, attributedString: attributedString, font: font)
                }

                if ProcessInfo.processInfo.environment["XCUI_TESTING"] == "1" {
                    postHighlightDiagnosticsIfNeeded(from: attributedString, language: language)
                }

                // Restore selection after update
                restoreSelectionIfValid(selectedRange, in: textView)

                // Preserve typing attributes so newlines / newly typed text doesn't reset styling
                restoreTypingAttributes(typingAttributes, in: textView)

                self.isProgrammaticUpdate = false

                // Updating text storage can leave the ruler stale until the next scroll event.
                refreshRulerAfterHighlight(in: textView)
            }
        }

        func applyHighlightAttributes(textStorage: NSTextStorage, attributedString: NSAttributedString, font: NSFont) {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let applyLength = min(textStorage.length, attributedString.length)
            let applyRange = NSRange(location: 0, length: applyLength)

            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            attributedString.enumerateAttributes(in: applyRange, options: []) { attrs, range, _ in
                var merged: [NSAttributedString.Key: Any] = [
                    .font: font
                ]
                if let fg = attrs[.foregroundColor] {
                    merged[.foregroundColor] = fg
                }
                textStorage.addAttributes(merged, range: range)
            }

            textStorage.endEditing()
        }

        private func postHighlightDiagnosticsIfNeeded(from attributedString: NSAttributedString, language: String) {
            let diagnostics = Self.buildHighlightDiagnostics(from: attributedString, language: language)
            NotificationCenter.default.post(
                name: .editorHighlightDiagnosticsUpdated,
                object: nil,
                userInfo: ["diagnostics": diagnostics]
            )
        }

        private func restoreSelectionIfValid(_ selectedRange: NSRange, in textView: NSTextView) {
            if selectedRange.location != NSNotFound,
               selectedRange.location + selectedRange.length <= (textView.string as NSString).length {
                textView.setSelectedRange(selectedRange)
            }
        }

        private func restoreTypingAttributes(
            _ typingAttributes: [NSAttributedString.Key: Any], 
            in textView: NSTextView
        ) {
            textView.typingAttributes = typingAttributes
        }

        private func refreshRulerAfterHighlight(in textView: NSTextView) {
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            if let scrollView = textView.enclosingScrollView {
                scrollView.verticalRulerView?.needsDisplay = true
                scrollView.tile()
            }
        }

        static func buildHighlightDiagnostics(from attributed: NSAttributedString, language: String) -> String {
            let fullRange = NSRange(location: 0, length: attributed.length)
            var unique: Set<String> = []

            func normalizeLanguage(_ raw: String) -> String {
                var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if s.hasPrefix("language_") {
                    s.removeFirst("language_".count)
                }
                if s.hasPrefix(".") {
                    s.removeFirst()
                }
                switch s {
                case "js": return "javascript"
                case "ts": return "typescript"
                case "py": return "python"
                default: return s
                }
            }

            func rgbaKey(for color: NSColor) -> String? {
                guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
                return "\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent),\(rgb.alphaComponent)"
            }

            attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, _, _ in
                guard let c = value as? NSColor else { return }
                if let key = rgbaKey(for: c) {
                    unique.insert(key)
                }
            }

            func containsColor(_ target: NSColor) -> Bool {
                guard let targetKey = rgbaKey(for: target) else { return false }
                return unique.contains(targetKey)
            }

            let normalized = normalizeLanguage(language)

            let languageEnum = CodeLanguage(rawValue: normalized) ?? .unknown
            let module = LanguageModuleManager.shared.getModule(for: languageEnum)
            let moduleId = module?.id.rawValue ?? "none"

            if let provider = module as? HighlightDiagnosticsPaletteProviding {
                var parts: [String] = [
                    "lang=\(normalized)",
                    "module=\(moduleId)",
                    "unique=\(unique.count)"
                ]

                for swatch in provider.highlightDiagnosticsPalette {
                    parts.append("\(swatch.name)=\(containsColor(swatch.color))")
                }

                return parts.joined(separator: ";")
            }

            // Fallback: expose a few known system colors to help debug non-module highlighting.
            let hasIndigo = containsColor(.systemIndigo)
            let hasTeal = containsColor(.systemTeal)
            let hasYellow = containsColor(.systemYellow)
            let hasPink = containsColor(.systemPink)
            let hasOrange = containsColor(.systemOrange)
            let hasBlue = containsColor(.systemBlue)
            let hasGray = containsColor(.systemGray)

            return "lang=\(normalized);module=\(moduleId);unique=\(unique.count);indigo=\(hasIndigo);teal=\(hasTeal);yellow=\(hasYellow);pink=\(hasPink);orange=\(hasOrange);blue=\(hasBlue);gray=\(hasGray)"
        }

        @MainActor
        private func scheduleHighlight(for text: String, in textView: NSTextView, language: String, font: NSFont) {
            pendingHighlightTask?.cancel()
            pendingHighlightTask = Task { [weak self, weak textView] in
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                guard let self, let textView else { return }
                await MainActor.run {
                    self.performAsyncHighlight(for: text, in: textView, language: language, font: font)
                }
            }
        }

        @MainActor
        fileprivate func handleDidProcessEditing(text: String) {
            if isProgrammaticUpdate { return }
            guard let textView = attachedTextView else { return }
            scheduleHighlight(
                for: text,
                in: textView,
                language: parent.language,
                font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            )
        }

        @MainActor
        func textDidChange(_ notification: Notification) {
            if isProgrammaticUpdate { return }
            guard let textView = notification.object as? NSTextView else { return }

            // Mutate bindings on main actor
            let newText = textView.string
            let newRange = textView.selectedRange

            self.parent.text = newText
            self.parent.selectedRange = newRange

            // Update the selection context with current selected text and range
            updateSelectionContext(from: textView)

            // Fallback highlight scheduling. Some edit paths may not reliably trigger NSTextStorageDelegate.
            scheduleHighlight(
                for: newText,
                in: textView,
                language: parent.language,
                font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            )
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            if isProgrammaticUpdate || isProgrammaticSelectionUpdate { return }
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.selectedRange = textView.selectedRange
            updateSelectionContext(from: textView)
        }

        @MainActor
        private func updateSelectionContext(from textView: NSTextView) {
            let range = textView.selectedRange
            if range.location != NSNotFound,
               range.length > 0,
               range.location + range.length <= (textView.string as NSString).length {
                let selected = (textView.string as NSString).substring(with: range)
                parent.selectionContext.selectedText = selected
                parent.selectionContext.selectedRange = range
            } else {
                parent.selectionContext.selectedText = ""
                parent.selectionContext.selectedRange = nil
            }
        }
    }
}
