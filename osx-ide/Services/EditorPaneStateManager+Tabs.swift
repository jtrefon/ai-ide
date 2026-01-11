import Foundation

extension EditorPaneStateManager {
    struct EditorTab: Identifiable, Equatable {
        let id: UUID
        var filePath: String
        var language: String
        var content: String
        var isDirty: Bool
        var selectedRange: NSRange?

        init(filePath: String, language: String, content: String, isDirty: Bool, selectedRange: NSRange? = nil) {
            self.id = UUID()
            self.filePath = filePath
            self.language = language
            self.content = content
            self.isDirty = isDirty
            self.selectedRange = selectedRange
        }
    }

    func closeTab(filePath: String) {
        tabManager.closeTab(filePath: filePath, tabs: tabs) { [weak self] id in
            self?.closeTab(id: id)
        }
    }

    func renameTab(oldPath: String, newPath: String) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == oldPath }) else { return }
        tabs[idx].filePath = newPath

        if activeTabID == tabs[idx].id {
            selectedFile = newPath
            fileEditorService.selectedFile = newPath
        }

        endWatchingFile(at: oldPath)
        beginWatchingFile(at: newPath)
    }

    func activateTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        persistActiveEditorStateToTab()
        activeTabID = id

        let tab = tabs[idx]
        beginWatchingFile(at: tab.filePath)
        isLoadingFile = true
        defer { isLoadingFile = false }
        selectedFile = tab.filePath
        editorLanguage = tab.language
        editorContent = tab.content
        isDirty = tab.isDirty
        selectedRange = tab.selectedRange
    }

    func activateTab(filePath: String) {
        tabManager.activateTabByFilePath(filePath: filePath, tabs: tabs) { [weak self] id in
            self?.activateTab(id: id)
        }
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: idx)
        endWatchingFile(at: removed.filePath)

        if activeTabID == removed.id {
            if let newActive = tabs.last {
                activateTab(id: newActive.id)
            } else {
                newFile()
            }
        }
    }

    func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id: id)
    }

    func closeOtherTabs(keeping id: UUID) {
        guard let keepIdx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let keep = tabs[keepIdx]
        let removedPaths = tabs.filter { $0.id != id }.map { $0.filePath }
        for path in removedPaths {
            endWatchingFile(at: path)
        }
        tabs = [keep]
        activateTab(id: keep.id)
    }

    func activateNextTab() {
        guard let nextID = tabManager.nextTabID(activeTabID: activeTabID, tabs: tabs) else { return }
        activateTab(id: nextID)
    }

    func activatePreviousTab() {
        guard let prevID = tabManager.previousTabID(activeTabID: activeTabID, tabs: tabs) else { return }
        activateTab(id: prevID)
    }

    func persistActiveEditorStateToTab() {
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabs[idx].content = editorContent
        tabs[idx].language = editorLanguage
        tabs[idx].isDirty = isDirty
        tabs[idx].selectedRange = selectedRange
    }

    func updateActiveTabFromEditor() {
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabs[idx].content = editorContent
        tabs[idx].language = editorLanguage
        tabs[idx].isDirty = true
    }

    func updateActiveTabSelectionFromEditor() {
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabs[idx].selectedRange = selectedRange
    }
}
