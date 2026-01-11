import Foundation

extension EditorPaneStateManager {
    func beginWatchingFile(at path: String) {
        fileWatchCoordinator.beginWatchingFile(at: path) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFileSystemEvent(event, forPath: path)
            }
        }
    }

    func endWatchingFile(at path: String) {
        fileWatchCoordinator.endWatchingFile(at: path)
    }

    func stopWatchingAllFiles(except keepPath: String? = nil) {
        fileWatchCoordinator.stopWatchingAllFiles(except: keepPath)
    }

    func handleFileSystemEvent(_ event: DispatchSource.FileSystemEvent, forPath path: String) {
        fileWatchCoordinator.handleFileSystemEvent(
            event,
            forPath: path,
            scheduleReload: { [weak self] in self?.scheduleReload(for: path) },
            scheduleWatchRestart: { [weak self] attempt in self?.scheduleWatchRestart(for: path, attempt: attempt) }
        )
    }

    func scheduleWatchRestart(for path: String, attempt: Int = 0) {
        fileWatchCoordinator.scheduleWatchRestart(for: path, attempt: attempt) { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: path) {
                self.beginWatchingFile(at: path)
                self.scheduleReload(for: path)
            } else {
                self.scheduleWatchRestart(for: path, attempt: attempt + 1)
            }
        }
    }

    func scheduleReload(for path: String) {
        fileWatchCoordinator.scheduleReload(for: path) { [weak self] in
            self?.reloadFileFromDisk(for: path)
        }
    }

    func reloadFileFromDisk(for path: String) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == path }) else { return }
        guard shouldReloadTab(at: idx, forPath: path) else { return }

        let url = URL(fileURLWithPath: path)
        guard shouldReloadFromURL(url) else { return }

        guard let newContent = readFileContent(from: url) else { return }
        guard newContent != tabs[idx].content else { return }

        applyReloadedContent(newContent, tabIndex: idx)
    }

    func shouldReloadTab(at index: Int, forPath path: String) -> Bool {
        guard !tabs[index].isDirty else { return false }
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return true
    }

    func shouldReloadFromURL(_ url: URL) -> Bool {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return !isDirectory
    }

    func readFileContent(from url: URL) -> String? {
        switch fileSystemService.readFileResult(at: url) {
        case .success(let content):
            return content
        case .failure:
            return nil
        }
    }

    func applyReloadedContent(_ content: String, tabIndex: Int) {
        tabs[tabIndex].content = content
        tabs[tabIndex].isDirty = false

        if activeTabID == tabs[tabIndex].id {
            isLoadingFile = true
            defer { isLoadingFile = false }
            editorContent = content
            isDirty = false
        }
    }
}
