//
//  IndexerActor.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

public actor IndexerActor {
    private let database: DatabaseManager
    private let config: IndexConfiguration
    
    public init(database: DatabaseManager, config: IndexConfiguration = .default) {
        self.database = database
        self.config = config
    }
    
    public func indexFile(at url: URL) async throws {
        // Skip if matches exclude patterns
        if shouldExclude(url) {
            return
        }

        let language = LanguageDetector.detect(at: url)

        // Basic metadata extraction for Phase 1
        let resourceId = url.absoluteString // Simple ID for now
        let fileModTime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970

        let existingModTime: Double? = (try? database.getResourceLastModified(resourceId: resourceId)) ?? nil
        if let fileModTime,
           let existingModTime,
           abs(existingModTime - fileModTime) < 0.000_001 {
            // Already indexed for this exact file version; skip.
            return
        }

        let timestamp = fileModTime ?? Date().timeIntervalSince1970
        
        // Read file content
        let content = try String(contentsOf: url, encoding: .utf8)
        let contentHash = computeHash(for: content)
        
        let sql = """
        INSERT INTO resources (id, path, language, last_modified, content_hash, quality_score)
        VALUES ('\(resourceId)', '\(url.path)', '\(language.rawValue)', \(timestamp), '\(contentHash)', 0.0)
        ON CONFLICT(id) DO UPDATE SET
            last_modified = \(timestamp),
            content_hash = '\(contentHash)',
            language = '\(language.rawValue)';
        """
        
        try database.execute(sql: sql)
        
        // Extract symbols if supported language
        let symbols: [Symbol]
        switch language {
        case .swift:
            symbols = SwiftParser.parse(content: content, resourceId: resourceId)
        case .javascript:
            symbols = JavaScriptParser.parse(content: content, resourceId: resourceId)
        case .typescript:
            symbols = TypeScriptParser.parse(content: content, resourceId: resourceId)
        case .python:
            symbols = PythonParser.parse(content: content, resourceId: resourceId)
        default:
            symbols = []
        }

        if !symbols.isEmpty {
            try database.deleteSymbols(for: resourceId)
            try database.saveSymbols(symbols)
        }
    }
    
    public func removeFile(at url: URL) async throws {
        let resourceId = url.absoluteString
        let sql = "DELETE FROM resources WHERE id = '\(resourceId)';"
        try database.execute(sql: sql)
        // Cascade delete should handle symbols, but let's be safe if we didn't enable foreign keys
        try database.deleteSymbols(for: resourceId)
    }
    
    private func computeHash(for content: String) -> String {
        // Simple hash for now, avoiding CryptoKit dependency for simplicity in this phase
        return String(content.hashValue)
    }
    
    private func shouldExclude(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
        let components = path.split(separator: "/").map(String.init)

        for pattern in config.excludePatterns {
            let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { continue }

            if p.contains("*") {
                let needle = p.replacingOccurrences(of: "*", with: "")
                if !needle.isEmpty, path.contains(needle) { return true }
                continue
            }

            if p.contains("/") {
                let needle = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !needle.isEmpty, path.contains(needle) { return true }
                continue
            }

            if components.contains(p) { return true }
        }

        return false
    }
}
