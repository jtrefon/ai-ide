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
            if url.lastPathComponent == ".ide" {
                enumerator.skipDescendants()
                continue
            }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory {
                if Self.isIndexableFile(url) && !Self.shouldExclude(url, excludePatterns: excludePatterns) {
                    results.append(url)
                }
            }
        }
        return results
    }

    private static func isIndexableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        let allowed: Set<String> = [
            "swift", "js", "ts", "py", "html", "css", "json", "yaml", "yml", "md", "markdown"
        ]
        return allowed.contains(ext)
    }

    private static func shouldExclude(_ url: URL, excludePatterns: [String]) -> Bool {
        let path = url.path
        for pattern in excludePatterns {
            if path.contains(pattern.replacingOccurrences(of: "*", with: "")) {
                return true
            }
        }
        return false
    }
}
