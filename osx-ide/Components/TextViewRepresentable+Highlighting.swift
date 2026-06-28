import SwiftUI
import AppKit

extension TextViewRepresentable.Coordinator {

    @MainActor
    func textDidChange(_ notification: Notification) {
        if isProgrammaticUpdate { return }
        guard let textView = notification.object as? NSTextView else { return }

        let newText = textView.string
        let newRange = textView.selectedRange

        self.parent.text = newText
        self.parent.selectedRange = newRange

        updateSelectionContext(from: textView)

        scheduleAutomaticInlineCompletionIfNeeded(for: textView)
    }

    @MainActor
    func textViewDidChangeSelection(_ notification: Notification) {
        if isProgrammaticUpdate || isProgrammaticSelectionUpdate { return }
        guard let textView = notification.object as? NSTextView else { return }
        self.parent.selectedRange = textView.selectedRange
        updateSelectionContext(from: textView)
        (textView as? CodeEditorTextView)?.clearInlineSuggestion()
        invalidateInlineCompletion()
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
