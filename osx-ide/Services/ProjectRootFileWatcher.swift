import Foundation

/// File watcher that monitors project root for changes.
/// Uses an actor for thread-safe state management to avoid blocking UI.
actor ProjectRootFileWatcherActor {
    private let rootURL: URL
    private let eventBus: EventBusProtocol
    private let excludePatterns: [String]
    private let debounceNanoseconds: UInt64

    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var scanTask: Task<Void, Never>?
    private var snapshot: [String: FileSnapshot] = [:]
    private var isActive = false

    init(
        rootURL: URL,
        eventBus: EventBusProtocol,
        excludePatterns: [String],
        debounceMs: Int = 1000
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.eventBus = eventBus
        self.excludePatterns = excludePatterns
        self.debounceNanoseconds = UInt64(max(50, debounceMs)) * 1_000_000
    }

    func start() {
        stop()
        // Build initial snapshot and start watching
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let initialSnapshot = await self.buildSnapshotAsync()
            await self.setSnapshot(initialSnapshot)
            await self.startWatching()
        }
    }
    
    private func setSnapshot(_ newSnapshot: [String: FileSnapshot]) {
        snapshot = newSnapshot
    }
    
    private func startWatching() async {
        let fd = open(rootURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )
        weak var weakSelf = self
        source.setEventHandler {
            Task { [weak weakSelf] in await weakSelf?.scheduleScan() }
        }
        source.setCancelHandler {
            Task { [weak weakSelf] in await weakSelf?.closeDescriptor() }
        }
        self.source = source
        isActive = true
        source.resume()
    }

    func stop() {
        let wasActive = isActive
        isActive = false
        
        guard wasActive else {
            closeDescriptor()
            return
        }
        scanTask?.cancel()
        scanTask = nil
        source?.cancel()
        source = nil
    }

    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.performScan()
        }
    }

    private func performScan() async {
        let newSnapshot = await buildSnapshotAsync()
        let oldSnapshot = snapshot
        snapshot = newSnapshot
        
        let diff = diffSnapshots(old: oldSnapshot, new: newSnapshot)

        guard !diff.changedPaths.isEmpty else { return }

        for path in diff.createdPaths {
            eventBus.publish(FileCreatedEvent(url: URL(fileURLWithPath: path)))
        }
        for path in diff.modifiedPaths {
            eventBus.publish(FileModifiedEvent(url: URL(fileURLWithPath: path)))
        }
        for path in diff.deletedPaths {
            eventBus.publish(FileDeletedEvent(url: URL(fileURLWithPath: path)))
        }

        eventBus.publish(FileTreeRefreshRequestedEvent(paths: diff.changedPaths))
    }

    /// Async version of buildSnapshot that runs file enumeration off main thread
    private func buildSnapshotAsync() async -> [String: FileSnapshot] {
        await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return [:] }
            return await self.buildSnapshot()
        }.value
    }

    private func buildSnapshot() async -> [String: FileSnapshot] {
        let files = enumerateTrackedFiles(rootURL: rootURL, excludePatterns: excludePatterns)
        var result: [String: FileSnapshot] = [:]
        result.reserveCapacity(files.count)
        for url in files {
            let path = url.standardizedFileURL.path
            if let snapshot = FileSnapshot(url: url) {
                result[path] = snapshot
            }
        }
        return result
    }

    private func enumerateTrackedFiles(rootURL: URL, excludePatterns: [String]) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let relativePath = relativePath(from: rootURL, to: url)

            if isDirectory {
                if shouldExclude(relativePath: relativePath, excludePatterns: excludePatterns) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if shouldExclude(relativePath: relativePath, excludePatterns: excludePatterns) {
                continue
            }
            results.append(url)
        }
        return results
    }

    private func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full == rootPath { return "" }
        if full.hasPrefix(rootPath + "/") {
            return String(full.dropFirst(rootPath.count + 1))
        }
        return full
    }

    private func shouldExclude(relativePath: String, excludePatterns: [String]) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)

        for pattern in excludePatterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.contains("*") {
                let needle = trimmed.replacingOccurrences(of: "*", with: "")
                if !needle.isEmpty, normalized.contains(needle) { return true }
                continue
            }

            if trimmed.contains("/") {
                let needle = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !needle.isEmpty, normalized.contains(needle) { return true }
                continue
            }

            if components.contains(trimmed) { return true }
        }

        return false
    }

    private func diffSnapshots(
        old: [String: FileSnapshot],
        new: [String: FileSnapshot]
    ) -> (createdPaths: [String], modifiedPaths: [String], deletedPaths: [String], changedPaths: [String]) {
        let oldKeys = Set(old.keys)
        let newKeys = Set(new.keys)

        let created = newKeys.subtracting(oldKeys)
        let deleted = oldKeys.subtracting(newKeys)

        var modified: [String] = []
        modified.reserveCapacity(newKeys.count)
        for key in newKeys.intersection(oldKeys) {
            if old[key] != new[key] {
                modified.append(key)
            }
        }

        let createdPaths = created.sorted()
        let deletedPaths = deleted.sorted()
        let modifiedPaths = modified.sorted()
        let changedPaths = (createdPaths + deletedPaths + modifiedPaths)

        return (createdPaths, modifiedPaths, deletedPaths, changedPaths)
    }

    private func closeDescriptor() {
        guard fileDescriptor >= 0 else { return }
        close(fileDescriptor)
        fileDescriptor = -1
    }
}

/// Non-actor wrapper for backward compatibility with existing code
final class ProjectRootFileWatcher: @unchecked Sendable {
    private let actor: ProjectRootFileWatcherActor
    
    init(
        rootURL: URL,
        eventBus: EventBusProtocol,
        excludePatterns: [String],
        debounceMs: Int = 1000
    ) {
        self.actor = ProjectRootFileWatcherActor(
            rootURL: rootURL,
            eventBus: eventBus,
            excludePatterns: excludePatterns,
            debounceMs: debounceMs
        )
    }
    
    func start() {
        Task { await actor.start() }
    }
    
    func stop() {
        Task { await actor.stop() }
    }
}

private struct FileSnapshot: Equatable {
    let modifiedAt: Double
    let sizeBytes: Int64

    init?(url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let date = values.contentModificationDate,
                  let size = values.fileSize else {
                return nil
            }
            self.modifiedAt = date.timeIntervalSince1970
            self.sizeBytes = Int64(size)
        } catch {
            return nil
        }
    }
}
