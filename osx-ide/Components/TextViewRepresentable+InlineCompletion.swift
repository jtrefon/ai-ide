import AppKit
import SwiftUI

extension TextViewRepresentable.Coordinator {
    @MainActor
    func configureInlineCompletionHandlers() {
        let paneID = parent.paneID
        parent.inlineCompletionEngine.registerSuggestionHandler(for: paneID) { [weak self] presentation in
            InlineCompletionDebugStore.shared.update(paneID: paneID, presentation: presentation)
            guard let self, let textView = self.attachedTextView as? CodeEditorTextView else { return }
            if let presentation {
                textView.updateGhostSuggestion(presentation)
            } else {
                textView.clearInlineSuggestion()
            }
        }

        parent.inlineCompletionEngine.registerManualTriggerHandler(for: parent.paneID) { [weak self] in
            self?.triggerManualCompletion()
        }
    }

    @MainActor
    func unregisterInlineCompletionHandlers() {
        parent.inlineCompletionEngine.unregisterSuggestionHandler(for: parent.paneID)
        parent.inlineCompletionEngine.unregisterManualTriggerHandler(for: parent.paneID)
        InlineCompletionDebugStore.shared.update(paneID: parent.paneID, presentation: nil)
    }

    @MainActor
    func handleFileSwitch(textView: NSTextView) {
        guard let signalBridge else { return }
        (textView as? CodeEditorTextView)?.clearInlineSuggestion()
        InlineCompletionDebugStore.shared.update(paneID: parent.paneID, presentation: nil)
        signalBridge.invalidate()
    }

    @MainActor
    func triggerManualCompletion() {
        guard let signalBridge, let textView = attachedTextView else { return }
        let snapshot = makeSnapshot(from: textView, triggerReason: .manual)
        signalBridge.triggerManualRequest(snapshot: snapshot)
    }

    @MainActor
    func scheduleAutomaticInlineCompletionIfNeeded(for textView: NSTextView) {
        guard let signalBridge else { return }
        let snapshot = makeSnapshot(from: textView, triggerReason: .automatic)
        signalBridge.scheduleAutomaticRequest(snapshot: snapshot)
    }

    @MainActor
    func invalidateInlineCompletion() {
        InlineCompletionDebugStore.shared.update(paneID: parent.paneID, presentation: nil)
        signalBridge?.invalidate()
    }

    @MainActor
    func makeSnapshot(
        from textView: NSTextView,
        triggerReason: CompletionTriggerReason
    ) -> InlineCompletionEditorSnapshot {
        let selection = textView.selectedRange
        return InlineCompletionEditorSnapshot(
            paneID: parent.paneID,
            filePath: parent.filePath,
            language: currentLanguageIdentifier,
            buffer: textView.string,
            cursorPosition: selection.location,
            selectionLength: selection.length,
            isComposingText: textView.hasMarkedText(),
            triggerReason: triggerReason
        )
    }
}
