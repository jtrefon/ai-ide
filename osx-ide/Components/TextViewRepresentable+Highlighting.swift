import SwiftUI
import AppKit

extension TextViewRepresentable.Coordinator {
    private struct HighlightContext {
        let selectedRange: NSRange
        let typingAttributes: [NSAttributedString.Key: Any]
    }

    private struct HighlightTaskRequest {
        let text: String
        let language: String
        let font: NSFont
        let textView: NSTextView
        let context: HighlightContext
    }

    private struct ApplyHighlightRequest {
        let attributedString: NSAttributedString
        let textView: NSTextView
        let language: String
        let font: NSFont
        let context: HighlightContext
    }

    @MainActor
    func performAsyncHighlight(for text: String, in textView: NSTextView, language: String, font: NSFont) {
        currentHighlightTask?.cancel()

        let context = HighlightContext(
            selectedRange: textView.selectedRange,
            typingAttributes: textView.typingAttributes
        )

        currentHighlightTask = makeHighlightTask(
            HighlightTaskRequest(
                text: text,
                language: language,
                font: font,
                textView: textView,
                context: context
            )
        )
    }

    @MainActor
    private func makeHighlightTask(_ request: HighlightTaskRequest) -> Task<Void, Never> {
        Task {
            let attributedString = SyntaxHighlighter.shared.highlight(
                request.text,
                language: request.language,
                font: request.font
            )

            if Task.isCancelled { return }

            self.isProgrammaticUpdate = true
            applyHighlightResult(
                ApplyHighlightRequest(
                    attributedString: attributedString,
                    textView: request.textView,
                    language: request.language,
                    font: request.font,
                    context: request.context
                )
            )
            self.isProgrammaticUpdate = false

            refreshRulerAfterHighlight(in: request.textView)
        }
    }

    @MainActor
    private func applyHighlightResult(_ request: ApplyHighlightRequest) {
        if let textStorage = request.textView.textStorage {
            applyHighlightAttributes(textStorage: textStorage, attributedString: request.attributedString, font: request.font)
        }

        if ProcessInfo.processInfo.environment["XCUI_TESTING"] == "1" {
            postHighlightDiagnosticsIfNeeded(from: request.attributedString, language: request.language)
        }

        restoreSelectionIfValid(request.context.selectedRange, in: request.textView)
        restoreTypingAttributes(request.context.typingAttributes, in: request.textView)
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
            if let foregroundColor = attrs[.foregroundColor] {
                merged[.foregroundColor] = foregroundColor
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

        func rgbaKey(for color: NSColor) -> String? {
            guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
            return "\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent),\(rgb.alphaComponent)"
        }

        attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, _, _ in
            guard let color = value as? NSColor else { return }
            if let key = rgbaKey(for: color) {
                unique.insert(key)
            }
        }

        func containsColor(_ target: NSColor) -> Bool {
            guard let targetKey = rgbaKey(for: target) else { return false }
            return unique.contains(targetKey)
        }

        let normalized = LanguageIdentifierNormalizer.normalize(language)

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

        var parts: [String] = [
            "lang=\(normalized)",
            "module=\(moduleId)",
            "unique=\(unique.count)"
        ]
        parts.append("indigo=\(containsColor(.systemIndigo))")
        parts.append("teal=\(containsColor(.systemTeal))")
        parts.append("yellow=\(containsColor(.systemYellow))")
        parts.append("pink=\(containsColor(.systemPink))")
        parts.append("orange=\(containsColor(.systemOrange))")
        parts.append("blue=\(containsColor(.systemBlue))")
        parts.append("gray=\(containsColor(.systemGray))")
        return parts.joined(separator: ";")
    }

    @MainActor
    func scheduleHighlight(for text: String, in textView: NSTextView, language: String, font: NSFont) {
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
    private func editorFont(for textView: NSTextView) -> NSFont {
        textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    @MainActor
    private func scheduleHighlightForCurrentEditorText(in textView: NSTextView) {
        scheduleHighlight(
            for: textView.string,
            in: textView,
            language: parent.language,
            font: editorFont(for: textView)
        )
    }

    @MainActor
    func handleDidProcessEditing(text _: String) {
        if isProgrammaticUpdate { return }
        guard let textView = attachedTextView else { return }
        scheduleHighlightForCurrentEditorText(in: textView)
    }

    @MainActor
    func textDidChange(_ notification: Notification) {
        if isProgrammaticUpdate { return }
        guard let textView = notification.object as? NSTextView else { return }

        let newText = textView.string
        let newRange = textView.selectedRange

        self.parent.text = newText
        self.parent.selectedRange = newRange

        updateSelectionContext(from: textView)

        scheduleHighlightForCurrentEditorText(in: textView)
    }

    @MainActor
    func textViewDidChangeSelection(_ notification: Notification) {
        if isProgrammaticUpdate || isProgrammaticSelectionUpdate { return }
        guard let textView = notification.object as? NSTextView else { return }
        self.parent.selectedRange = textView.selectedRange
        updateSelectionContext(from: textView)
    }

    @MainActor
    func updateSelectionContext(from textView: NSTextView) {
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
