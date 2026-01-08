//
//  IndexerActor.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation
import CryptoKit

public actor IndexerActor {
    private let database: DatabaseStore
    private let config: IndexConfiguration
    
    public init(database: DatabaseStore, config: IndexConfiguration = .default) {
        self.database = database
        self.config = config
    }
    
    public func indexFile(at url: URL) async throws {
        await IndexLogger.shared.log("IndexerActor: Processing file \(url.path)")
        // Skip if matches exclude patterns
        if shouldExclude(url) {
            await IndexLogger.shared.log("IndexerActor: Skipping excluded file \(url.lastPathComponent)")
            return
        }

        let language = LanguageDetector.detect(at: url)

        // Basic metadata extraction for Phase 1
        let resourceId = url.absoluteString // Simple ID for now
        let fileModTime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970

        let existingModTime: Double? = (try? await database.getResourceLastModified(resourceId: resourceId)) ?? nil
        if let fileModTime,
           let existingModTime,
           abs(existingModTime - fileModTime) < 0.000_001 {
            // Modtimes can have limited resolution; verify hash before skipping.
            let content = try String(contentsOf: url, encoding: .utf8)
            let currentHash = computeHash(for: content)
            let existingHash = (try? await database.getResourceContentHash(resourceId: resourceId)) ?? nil

            if let existingHash, !existingHash.isEmpty, existingHash == currentHash {
                await IndexLogger.shared.log("IndexerActor: File \(url.lastPathComponent) already indexed (hash match), skipping")
                return
            }

            // If hash differs (or missing), continue indexing using the content we already loaded.
            await IndexLogger.shared.log("IndexerActor: File \(url.lastPathComponent) modtime matched but hash differs; reindexing")

            await IndexLogger.shared.log("IndexerActor: Indexing \(url.lastPathComponent) (Language: \(language.rawValue))")
            let timestamp = fileModTime

            try await database.upsertResourceAndFTS(
                resourceId: resourceId,
                path: url.path,
                language: language.rawValue,
                timestamp: timestamp,
                contentHash: currentHash,
                content: content
            )

            // Extract symbols if supported language
            let symbols: [Symbol]
            if let module = await LanguageModuleManager.shared.getModule(for: language) {
                symbols = module.symbolExtractor.extractSymbols(content: content, resourceId: resourceId)
            } else {
                symbols = []
            }

            if !symbols.isEmpty {
                await IndexLogger.shared.log("IndexerActor: Extracted \(symbols.count) symbols from \(url.lastPathComponent)")
                try await database.deleteSymbols(for: resourceId)
                try await database.saveSymbolsBatched(symbols)
            }

            return
        }

        await IndexLogger.shared.log("IndexerActor: Indexing \(url.lastPathComponent) (Language: \(language.rawValue))")
        let timestamp = fileModTime ?? Date().timeIntervalSince1970
        
        // Read file content
        let content = try String(contentsOf: url, encoding: .utf8)
        let contentHash = computeHash(for: content)
        
        let sql = """
        INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
        VALUES (?, ?, ?, ?, ?, 0.0)
        ON CONFLICT(id) DO UPDATE SET
            last_modified = excluded.last_modified,
            content_hash = excluded.content_hash,
            language = excluded.language;
        """
        
        try await database.upsertResourceAndFTS(
            resourceId: resourceId,
            path: url.path,
            language: language.rawValue,
            timestamp: timestamp,
            contentHash: contentHash,
            content: content
        )
        
        // Extract symbols if supported language
        let symbols: [Symbol]
        if let module = await LanguageModuleManager.shared.getModule(for: language) {
            symbols = module.symbolExtractor.extractSymbols(content: content, resourceId: resourceId)
        } else {
            symbols = []
        }

        if !symbols.isEmpty {
            await IndexLogger.shared.log("IndexerActor: Extracted \(symbols.count) symbols from \(url.lastPathComponent)")
            try await database.deleteSymbols(for: resourceId)
            try await database.saveSymbolsBatched(symbols)
        }
    }
    
    public func removeFile(at url: URL) async throws {
        let resourceId = url.absoluteString
        try await database.deleteResource(resourceId: resourceId)

        // Cascade delete should handle symbols, but let's be safe if we didn't enable foreign keys
        try await database.deleteSymbols(for: resourceId)
    }
    
    private func computeHash(for content: String) -> String {
        guard let data = content.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func shouldExclude(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
        let relativePath: String
        
        // Try to get a relative path if possible for better matching
        // In a real scenario, we'd pass the project root here.
        // For now, we'll use the last component or the full path if not possible.
        relativePath = path

        for pattern in config.excludePatterns {
            if GlobMatcher.match(path: relativePath, pattern: pattern) {
                return true
            }
            
            // Also check components for simple directory names
            let components = relativePath.split(separator: "/").map(String.init)
            if components.contains(pattern) {
                return true
            }
        }

        return false
    }
}
