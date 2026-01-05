//
//  CodeEditorView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

// TODO: Enable selection passing to the AI chat panel for context-aware code actions.

import SwiftUI
import AppKit

// CodeSelectionContext moved to Services/CodeSelectionContext.swift

struct CodeEditorView: View {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    var showLineNumbers: Bool = true
    var wordWrap: Bool = false
    var fontSize: Double = AppConstants.Editor.defaultFontSize
    var fontFamily: String = "SF Mono"
    
    var body: some View {
        GeometryReader { geometry in
            // Text editor (use AppKit's own NSScrollView; avoid nesting in SwiftUI ScrollView)
            TextViewRepresentable(
                text: $text,
                language: language,
                selectedRange: $selectedRange,
                selectionContext: selectionContext,
                showLineNumbers: showLineNumbers,
                wordWrap: wordWrap,
                fontSize: fontSize,
                fontFamily: fontFamily
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private final class TextStorageDelegateProxy: NSObject, NSTextStorageDelegate {
    weak var coordinator: TextViewRepresentable.Coordinator?

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        if !editedMask.contains(.editedCharacters) { return }
        let text = textStorage.string
        Task { @MainActor [weak coordinator] in
            coordinator?.handleDidProcessEditing(text: text)
        }
    }
}

@MainActor
struct TextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    var showLineNumbers: Bool
    var wordWrap: Bool
    var fontSize: Double
    var fontFamily: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = resolveEditorFont(fontFamily: fontFamily, fontSize: fontSize)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        // UI Tests need a stable identifier; otherwise `app.textViews.firstMatch` can
        // accidentally match the AI chat input instead of the editor.
        textView.setAccessibilityIdentifier("CodeEditorTextView")
        
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        
        // Set initial text without syntax highlighting to avoid initialization issues
        context.coordinator.isProgrammaticUpdate = true
        textView.string = text
        context.coordinator.isProgrammaticUpdate = false

        // Assign delegate only after initial programmatic setup to avoid publishing SwiftUI state during view updates.
        textView.delegate = context.coordinator
        context.coordinator.attach(textView: textView)
        textView.textStorage?.delegate = context.coordinator.textStorageDelegateProxy
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false

        DispatchQueue.main.async {
            applyWordWrap(wordWrap, to: scrollView, textView: textView)
        }

        if showLineNumbers {
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            scrollView.verticalRulerView = ModernLineNumberRulerView(scrollView: scrollView, textView: textView)

            // Ensure the ruler is laid out and painted on first draw (otherwise it can appear only after scrolling).
            DispatchQueue.main.async {
                scrollView.tile()
                scrollView.verticalRulerView?.needsDisplay = true
            }
        }
        
        // Apply syntax highlighting after the view is set up asynchronously
        context.coordinator.performAsyncHighlight(for: text, in: textView, language: language, font: resolveEditorFont(fontFamily: fontFamily, fontSize: fontSize))
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let resolvedFont = resolveEditorFont(fontFamily: fontFamily, fontSize: fontSize)
        var needsRehighlight = false
        if textView.font != resolvedFont {
            textView.font = resolvedFont
            needsRehighlight = true
        }

        if let ruler = scrollView.verticalRulerView as? ModernLineNumberRulerView {
            ruler.updateFont(resolvedFont)
        }

        DispatchQueue.main.async {
            applyWordWrap(wordWrap, to: scrollView, textView: textView)
        }
        
        // Avoid unnecessary updates to prevent flicker/blanking
        let current = textView.string
        if current != text {
            // Our highlighter now applies attributes in-place and does not replace characters.
            // When SwiftUI updates the bound text (e.g. opening a file), we must update the NSTextView content first.
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false

            context.coordinator.performAsyncHighlight(for: text, in: textView, language: language, font: resolvedFont)
        } else if needsRehighlight {
            // Some AppKit updates (notably changing `textView.font`) can implicitly reset
            // existing text storage attributes, which will wipe syntax colors.
            // Ensure the highlighter runs again even when the underlying text is unchanged.
            context.coordinator.performAsyncHighlight(for: current, in: textView, language: language, font: resolvedFont)
        }
        
        
        // Update selected range if needed
        if let range = selectedRange,
           range.location != NSNotFound,
           range.location + range.length <= (textView.string as NSString).length {
            context.coordinator.isProgrammaticSelectionUpdate = true
            defer { context.coordinator.isProgrammaticSelectionUpdate = false }
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        let shouldShowRuler = showLineNumbers
        if scrollView.hasVerticalRuler != shouldShowRuler || scrollView.rulersVisible != shouldShowRuler {
            scrollView.hasVerticalRuler = shouldShowRuler
            scrollView.rulersVisible = shouldShowRuler
            if shouldShowRuler && scrollView.verticalRulerView == nil {
                scrollView.verticalRulerView = ModernLineNumberRulerView(scrollView: scrollView, textView: textView)
            }
        }
        
        // The selection context is now available for the AI chat panel or other consumers.
    }

    private func resolveEditorFont(fontFamily: String, fontSize: Double) -> NSFont {
        let size = CGFloat(fontSize)

        if let font = NSFont(name: fontFamily, size: size) {
            return font
        }

        if let font = NSFontManager.shared.font(withFamily: fontFamily, traits: .fixedPitchFontMask, weight: 5, size: size) {
            return font
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func applyWordWrap(_ enabled: Bool, to scrollView: NSScrollView, textView: NSTextView) {
        guard let container = textView.textContainer else { return }

        if enabled {
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: TextViewRepresentable
        var isProgrammaticUpdate = false
        var isProgrammaticSelectionUpdate = false
        private var currentHighlightTask: Task<Void, Never>?
        private var pendingHighlightWorkItem: DispatchWorkItem?
        private weak var attachedTextView: NSTextView?
        fileprivate let textStorageDelegateProxy: TextStorageDelegateProxy
        
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
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if isProgrammaticUpdate { return true }
            guard let replacementString else { return true }

            #if DEBUG
            print("[Editor] shouldChangeTextIn replacement=\(String(describing: replacementString)) range=\(affectedCharRange) selected=\(textView.selectedRange)")
            #endif

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
        private func handleAutoPair(open: String, close: String, in textView: NSTextView, affectedCharRange: NSRange) -> Bool {
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
                    let fullRange = NSRange(location: 0, length: textStorage.length)
                    let applyLength = min(textStorage.length, attributedString.length)
                    let applyRange = NSRange(location: 0, length: applyLength)
                    textStorage.beginEditing()

                    // Always reset base attributes first so a partial/highlight miss doesn't leave stale styles behind.
                    textStorage.setAttributes([
                        .font: font,
                        .foregroundColor: NSColor.labelColor
                    ], range: fullRange)

                    // Apply attribute runs from the highlighter output.
                    // This keeps the underlying characters intact while allowing modules to define styling.
                    attributedString.enumerateAttributes(in: applyRange, options: []) { attrs, range, _ in
                        var merged = attrs
                        // Enforce editor font consistently
                        merged[.font] = font
                        textStorage.setAttributes(merged, range: range)
                    }

                    textStorage.endEditing()
                }
                
                // Restore selection after update
                if selectedRange.location != NSNotFound,
                   selectedRange.location + selectedRange.length <= (textView.string as NSString).length {
                    textView.setSelectedRange(selectedRange)
                }

                // Preserve typing attributes so newlines / newly typed text doesn't reset styling
                textView.typingAttributes = typingAttributes
                
                self.isProgrammaticUpdate = false

                // Updating text storage can leave the ruler stale until the next scroll event.
                if let container = textView.textContainer {
                    textView.layoutManager?.ensureLayout(for: container)
                }
                if let scrollView = textView.enclosingScrollView {
                    scrollView.verticalRulerView?.needsDisplay = true
                    scrollView.tile()
                }
            }
        }

        @MainActor
        private func scheduleHighlight(for text: String, in textView: NSTextView, language: String, font: NSFont) {
            pendingHighlightWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.performAsyncHighlight(for: text, in: textView, language: language, font: font)
            }

            pendingHighlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
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

#Preview {
    CodeEditorView(
        text: .constant("func helloWorld() {\n    print(\"Hello, World!\")\n}"),
        language: "swift",
        selectedRange: .constant(nil),
        selectionContext: CodeSelectionContext(),
        showLineNumbers: true,
        wordWrap: false,
        fontSize: AppConstants.Editor.defaultFontSize,
        fontFamily: "SF Mono"
    )
    .frame(height: 300)
}
