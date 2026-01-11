import Foundation

@MainActor
final class EditorTabManager {
    func closeTab(filePath: String, tabs: [EditorPaneStateManager.EditorTab], closeTabByID: (UUID) -> Void) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == filePath }) else { return }
        closeTabByID(tabs[idx].id)
    }

    func activateTabByFilePath(filePath: String, tabs: [EditorPaneStateManager.EditorTab], activateTabByID: (UUID) -> Void) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == filePath }) else { return }
        activateTabByID(tabs[idx].id)
    }

    func nextTabID(activeTabID: UUID?, tabs: [EditorPaneStateManager.EditorTab]) -> UUID? {
        guard !tabs.isEmpty else { return nil }
        guard let activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return tabs[0].id }
        return tabs[(idx + 1) % tabs.count].id
    }

    func previousTabID(activeTabID: UUID?, tabs: [EditorPaneStateManager.EditorTab]) -> UUID? {
        guard !tabs.isEmpty else { return nil }
        guard let activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return tabs[0].id }
        return tabs[(idx - 1 + tabs.count) % tabs.count].id
    }
}
