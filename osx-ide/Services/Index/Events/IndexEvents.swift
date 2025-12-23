//
//  IndexEvents.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

// MARK: - File Events

public struct FileCreatedEvent: Event {
    public let url: URL
    public init(url: URL) { self.url = url }
}

public struct FileModifiedEvent: Event {
    public let url: URL
    public init(url: URL) { self.url = url }
}

public struct FileDeletedEvent: Event {
    public let url: URL
    public init(url: URL) { self.url = url }
}

public struct FileRenamedEvent: Event {
    public let oldUrl: URL
    public let newUrl: URL
    public init(oldUrl: URL, newUrl: URL) {
        self.oldUrl = oldUrl
        self.newUrl = newUrl
    }
}

// MARK: - Indexing Events

public struct IndexingStartedEvent: Event {
    public init() {}
}

public struct IndexingProgressEvent: Event {
    public let processedCount: Int
    public let totalCount: Int
    public let currentFile: URL?
    
    public init(processedCount: Int, totalCount: Int, currentFile: URL? = nil) {
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.currentFile = currentFile
    }
}

public struct IndexingCompletedEvent: Event {
    public let indexedCount: Int
    public let duration: TimeInterval
    
    public init(indexedCount: Int, duration: TimeInterval) {
        self.indexedCount = indexedCount
        self.duration = duration
    }
}

public struct AIEnrichmentStartedEvent: Event {
    public init() {}
}

public struct AIEnrichmentProgressEvent: Event {
    public let processedCount: Int
    public let totalCount: Int
    public let currentFile: URL?

    public init(processedCount: Int, totalCount: Int, currentFile: URL? = nil) {
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.currentFile = currentFile
    }
}

public struct AIEnrichmentCompletedEvent: Event {
    public let processedCount: Int
    public let duration: TimeInterval

    public init(processedCount: Int, duration: TimeInterval) {
        self.processedCount = processedCount
        self.duration = duration
    }
}

// MARK: - Memory Events

public struct MemoryCapturedEvent: Event {
    public let tier: String // "short", "mid", "long"
    public let content: String
    
    public init(tier: String, content: String) {
        self.tier = tier
        self.content = content
    }
}
