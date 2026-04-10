import Foundation

@MainActor
final class EditorSignalBridge {
    private let paneID: FileEditorStateManager.PaneID
    private let engine: InlineCompletionEngine
    private let settingsStore: InlineCompletionSettingsStore
    private var debounceTask: Task<Void, Never>?

    init(
        paneID: FileEditorStateManager.PaneID,
        engine: InlineCompletionEngine,
        settingsStore: InlineCompletionSettingsStore = InlineCompletionSettingsStore()
    ) {
        self.paneID = paneID
        self.engine = engine
        self.settingsStore = settingsStore
    }

    func scheduleAutomaticRequest(snapshot: InlineCompletionEditorSnapshot) {
        debounceTask?.cancel()
        let debounceMs = settingsStore.load().debounceMilliseconds
        debounceTask = Task { [weak self] in
            guard let self else { return }
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            self.engine.requestCompletion(for: snapshot)
        }
    }

    func triggerManualRequest(snapshot: InlineCompletionEditorSnapshot) {
        debounceTask?.cancel()
        engine.requestCompletion(for: snapshot)
    }

    func invalidate() {
        debounceTask?.cancel()
        engine.invalidate(paneID)
    }
}
