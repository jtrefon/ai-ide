import Foundation
import Combine

@MainActor
public class IndexCoordinator {
    private let eventBus: EventBusProtocol
    private let indexer: IndexerActor
    private var cancellables = Set<AnyCancellable>()
    private let debounceSubject = PassthroughSubject<URL, Never>()
    private let config: IndexConfiguration
    private var isEnabled: Bool
    private var reindexTask: Task<Void, Never>?
    private var singleFileTasks: [UUID: Task<Void, Never>] = [:]
    private var generation: UInt64 = 0
    
    public init(eventBus: EventBusProtocol, indexer: IndexerActor, config: IndexConfiguration = .default, projectRoot: URL? = nil) {
        self.eventBus = eventBus
        self.indexer = indexer
        self.config = config
        self.isEnabled = config.enabled
        
        if let projectRoot = projectRoot {
            Task {
                await IndexLogger.shared.setup(projectRoot: projectRoot)
                await IndexLogger.shared.log("IndexCoordinator initialized with root: \(projectRoot.path)")
            }
        }
        
        setupSubscriptions()
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    public func stop() {
        generation &+= 1
        isEnabled = false

        reindexTask?.cancel()
        reindexTask = nil

        for (_, task) in singleFileTasks {
            task.cancel()
        }
        singleFileTasks.removeAll()

        cancellables.removeAll()
    }

    public func reindexProject(rootURL: URL) {
        guard isEnabled else { 
            Task { @MainActor in await IndexLogger.shared.log("Reindex skipped: Indexing is disabled") }
            return 
        }

        generation &+= 1
        let localGeneration = generation

        reindexTask?.cancel()

        reindexTask = Task { @MainActor in
            let start = Date()
            await IndexLogger.shared.log("Starting project reindex for: \(rootURL.path)")
            await eventBus.publish(IndexingStartedEvent())

            let files = Self.enumerateProjectFiles(rootURL: rootURL, excludePatterns: config.excludePatterns)
            let total = files.count
            await IndexLogger.shared.log("Found \(total) files to index")

            var processed = 0
            for file in files {
                if Task.isCancelled || localGeneration != generation { break }
                if !isEnabled { 
                    await IndexLogger.shared.log("Reindex aborted: Indexing was disabled during process")
                    break 
                }
                await eventBus.publish(IndexingProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
                do {
                    try await indexer.indexFile(at: file)
                    processed += 1
                } catch {
                    await IndexLogger.shared.log("Failed to index file \(file.path): \(error)")
                }
                await eventBus.publish(IndexingProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
            }

            if Task.isCancelled || localGeneration != generation { return }

            let duration = Date().timeIntervalSince(start)
            await IndexLogger.shared.log("Reindex completed: \(processed)/\(total) files in \(String(format: "%.2f", duration))s")
            await eventBus.publish(IndexingCompletedEvent(indexedCount: processed, duration: duration))
            await eventBus.publish(ProjectReindexCompletedEvent(indexedCount: processed, duration: duration))
        }
    }
    
    private func setupSubscriptions() {
        // Handle file events
        eventBus.subscribe(to: FileCreatedEvent.self) { [weak self] event in
            guard let self, self.isEnabled else { return }
            self.debounceSubject.send(event.url)
        }
        .store(in: &cancellables)
        
        eventBus.subscribe(to: FileModifiedEvent.self) { [weak self] event in
            guard let self, self.isEnabled else { return }
            self.debounceSubject.send(event.url)
        }
        .store(in: &cancellables)
        
        eventBus.subscribe(to: FileRenamedEvent.self) { [weak self] event in
            guard let self, self.isEnabled else { return }
            Task {
                try? await self.indexer.removeFile(at: event.oldUrl)
                self.debounceSubject.send(event.newUrl)
            }
        }
        .store(in: &cancellables)
        
        eventBus.subscribe(to: FileDeletedEvent.self) { [weak self] event in
            guard let self, self.isEnabled else { return }
            Task {
                try? await self.indexer.removeFile(at: event.url)
            }
        }
        .store(in: &cancellables)
        
        // Setup debounce pipeline
        debounceSubject
            .debounce(for: .milliseconds(config.debounceMs), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] url in
                self?.indexFile(url)
            }
            .store(in: &cancellables)
    }
    
    private func indexFile(_ url: URL) {
        let localGeneration = generation

        let id = UUID()
        let task = Task { @MainActor in
            do {
                guard isEnabled else { 
                    await IndexLogger.shared.log("Single file index skipped for \(url.path): Indexing disabled")
                    return 
                }
                await IndexLogger.shared.log("Indexing single file: \(url.path)")
                await eventBus.publish(IndexingStartedEvent())
                await eventBus.publish(IndexingProgressEvent(processedCount: 0, totalCount: 1, currentFile: url))
                if Task.isCancelled || localGeneration != generation { return }
                try await indexer.indexFile(at: url)
                if Task.isCancelled || localGeneration != generation { return }
                await eventBus.publish(IndexingProgressEvent(processedCount: 1, totalCount: 1, currentFile: url))
                await eventBus.publish(IndexingCompletedEvent(indexedCount: 1, duration: 0))
                await IndexLogger.shared.log("Successfully indexed single file: \(url.path)")
            } catch {
                await IndexLogger.shared.log("Failed to index file \(url.path): \(error)")
            }

            self.singleFileTasks[id] = nil
        }

        singleFileTasks[id] = task
    }

    public static func enumerateProjectFiles(rootURL: URL) -> [URL] {
        return enumerateProjectFiles(rootURL: rootURL, excludePatterns: [])
    }

    public static func enumerateProjectFiles(rootURL: URL, excludePatterns: [String]) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            let relativePath = relativePath(from: rootURL, to: url)

            if isDirectory {
                if url.lastPathComponent == ".ide" {
                    enumerator.skipDescendants()
                    continue
                }

                if shouldExclude(relativePath: relativePath, excludePatterns: excludePatterns) {
                    enumerator.skipDescendants()
                    continue
                }
                continue
            }

            if Self.isIndexableFile(url) && !Self.shouldExclude(relativePath: relativePath, excludePatterns: excludePatterns) {
                results.append(url)
            }
        }
        return results
    }

    private static func isIndexableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        let allowed: Set<String> = [
            "swift",
            "js", "jsx",
            "ts", "tsx",
            "py",
            "html", "css",
            "json", "yaml", "yml",
            "md", "markdown"
        ]
        return allowed.contains(ext)
    }

    public static func loadExcludePatterns(projectRoot: URL, defaultPatterns: [String]) -> [String] {
        let fileManager = FileManager.default
        let ideDir = projectRoot.appendingPathComponent(".ide", isDirectory: true)
        let excludeFile = ideDir.appendingPathComponent("index_exclude", isDirectory: false)

        do {
            try fileManager.createDirectory(at: ideDir, withIntermediateDirectories: true)
        } catch {
            return defaultPatterns
        }

        if !fileManager.fileExists(atPath: excludeFile.path) {
            let content = defaultExcludeFileContent(defaultPatterns: defaultPatterns)
            do {
                try content.write(to: excludeFile, atomically: true, encoding: .utf8)
            } catch {
                return defaultPatterns
            }
        }

        do {
            let raw = try String(contentsOf: excludeFile, encoding: .utf8)
            let custom = parseExcludeFile(raw)
            return mergeExcludePatterns(defaultPatterns: defaultPatterns, customPatterns: custom)
        } catch {
            return defaultPatterns
        }
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full == rootPath { return "" }
        if full.hasPrefix(rootPath + "/") {
            return String(full.dropFirst(rootPath.count + 1))
        }
        return full
    }

    private static func parseExcludeFile(_ content: String) -> [String] {
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("#") }
    }

    private static func mergeExcludePatterns(defaultPatterns: [String], customPatterns: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        merged.reserveCapacity(defaultPatterns.count + customPatterns.count)

        for p in defaultPatterns + customPatterns {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                merged.append(trimmed)
            }
        }
        return merged
    }

    private static func defaultExcludeFileContent(defaultPatterns: [String]) -> String {
        let header = """
# One pattern per line.
# Lines beginning with '#' are comments.
# Matching is path-based and intentionally simple; use directory names like 'node_modules' to exclude anywhere.

"""
        return header + defaultPatterns.joined(separator: "\n") + "\n"
    }

    private static func shouldExclude(relativePath: String, excludePatterns: [String]) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)

        for pattern in excludePatterns {
            let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { continue }

            if p.contains("*") {
                let needle = p.replacingOccurrences(of: "*", with: "")
                if !needle.isEmpty, normalized.contains(needle) { return true }
                continue
            }

            if p.contains("/") {
                let needle = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !needle.isEmpty, normalized.contains(needle) { return true }
                continue
            }

            if components.contains(p) { return true }
        }

        return false
    }
}
