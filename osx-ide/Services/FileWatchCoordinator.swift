import Foundation

@MainActor
final class FileWatchCoordinator {
    private var fileWatchers: [String: FileChangeMonitor] = [:]
    private var pendingReloads: [String: DispatchWorkItem] = [:]
    private var pendingWatchRestarts: [String: DispatchWorkItem] = [:]

    func beginWatchingFile(at path: String, onEvent: @escaping (DispatchSource.FileSystemEvent) -> Void) {
        guard fileWatchers[path] == nil else { return }
        let url = URL(fileURLWithPath: path)
        let watcher = FileChangeMonitor(
            url: url,
            queue: DispatchQueue(label: "FileChangeMonitor.\(url.lastPathComponent)")
        ) { event in
            onEvent(event)
        }
        fileWatchers[path] = watcher
        watcher.start()
    }

    func endWatchingFile(at path: String) {
        pendingReloads[path]?.cancel()
        pendingReloads.removeValue(forKey: path)

        pendingWatchRestarts[path]?.cancel()
        pendingWatchRestarts.removeValue(forKey: path)

        if let watcher = fileWatchers[path] {
            watcher.stop()
            fileWatchers.removeValue(forKey: path)
        }
    }

    func stopWatchingAllFiles(except keepPath: String? = nil) {
        let paths = fileWatchers.keys.filter { $0 != keepPath }
        for path in paths {
            endWatchingFile(at: path)
        }
    }

    func handleFileSystemEvent(
        _ event: DispatchSource.FileSystemEvent,
        forPath path: String,
        scheduleReload: @escaping () -> Void,
        scheduleWatchRestart: @escaping (_ attempt: Int) -> Void
    ) {
        if event.contains(.rename) || event.contains(.delete) || event.contains(.revoke) {
            endWatchingFile(at: path)
            scheduleWatchRestart(0)
            return
        }

        if event.contains(.write) || event.contains(.extend) || event.contains(.attrib) {
            scheduleReload()
        }
    }

    func scheduleWatchRestart(for path: String, attempt: Int = 0, work: @escaping () -> Void) {
        let maxAttempts = 5
        guard attempt < maxAttempts else { return }

        pendingWatchRestarts[path]?.cancel()
        let item = DispatchWorkItem(block: work)
        pendingWatchRestarts[path] = item
        let delay = 0.2 * Double(attempt + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func scheduleReload(for path: String, work: @escaping () -> Void) {
        pendingReloads[path]?.cancel()
        let item = DispatchWorkItem(block: work)
        pendingReloads[path] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
}
