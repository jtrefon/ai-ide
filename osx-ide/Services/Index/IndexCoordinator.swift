//
//  IndexCoordinator.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

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
    
    public init(eventBus: EventBusProtocol, indexer: IndexerActor, config: IndexConfiguration = .default) {
        self.eventBus = eventBus
        self.indexer = indexer
        self.config = config
        self.isEnabled = config.enabled
        
        setupSubscriptions()
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    public func reindexProject(rootURL: URL) {
        guard isEnabled else { return }

        Task {
            let start = Date()
            eventBus.publish(IndexingStartedEvent())

            let files = Self.enumerateProjectFiles(rootURL: rootURL, excludePatterns: config.excludePatterns)
            let total = files.count

            var processed = 0
            for file in files {
                if !isEnabled { break }
                eventBus.publish(IndexingProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
                try? await indexer.indexFile(at: file)
                processed += 1
                eventBus.publish(IndexingProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
            }

            let duration = Date().timeIntervalSince(start)
            eventBus.publish(IndexingCompletedEvent(indexedCount: processed, duration: duration))
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
        Task {
            do {
                guard isEnabled else { return }
                eventBus.publish(IndexingStartedEvent())
                eventBus.publish(IndexingProgressEvent(processedCount: 0, totalCount: 1, currentFile: url))
                try await indexer.indexFile(at: url)
                eventBus.publish(IndexingProgressEvent(processedCount: 1, totalCount: 1, currentFile: url))
                eventBus.publish(IndexingCompletedEvent(indexedCount: 1, duration: 0))
            } catch {
                print("Failed to index file \(url): \(error)")
            }
        }
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
