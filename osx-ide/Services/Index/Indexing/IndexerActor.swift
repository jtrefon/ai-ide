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

    private struct IndexResourceRequest {
        let url: URL
        let resourceId: String
        let languageRawValue: String
        let timestamp: Double
        let content: String
        let contentHash: String
        let language: CodeLanguage
    }

    public func indexFile(at url: URL) async throws {
        await IndexLogger.shared.log("IndexerActor: Processing file \(url.path)")
        guard !shouldExclude(url) else {
            await IndexLogger.shared.log("IndexerActor: Skipping excluded file \(url.lastPathComponent)")
            return
        }

        let language = LanguageDetector.detect(at: url)
        let resourceId = url.absoluteString
        let fileModTime = fileModificationTime(at: url)

        try await processFileIndexing(url: url, resourceId: resourceId, language: language, fileModTime: fileModTime)
    }

    private func processFileIndexing(url: URL, resourceId: String, language: CodeLanguage, fileModTime: Double?) async throws {
        if let skipDecision = try await shouldSkipIndexing(url: url, resourceId: resourceId, fileModTime: fileModTime) {
            try await handleSkipDecision(skipDecision, url: url, resourceId: resourceId, language: language)
        } else {
            try await indexFromDisk(url: url, resourceId: resourceId, language: language, timestamp: fileModTime)
        }
    }

    private func handleSkipDecision(
        _ skipDecision: SkipDecision,
        url: URL,
        resourceId: String,
        language: CodeLanguage
    ) async throws {
        if skipDecision.shouldSkip {
            await IndexLogger.shared.log(
                "IndexerActor: File \(url.lastPathComponent) already indexed (hash match), skipping"
            )
            return
        }

        await IndexLogger.shared.log(
            "IndexerActor: File \(url.lastPathComponent) modtime matched but hash differs; reindexing"
        )

        await IndexLogger.shared.log(
            "IndexerActor: Indexing \(url.lastPathComponent) (Language: \(language.rawValue))"
        )

        let request = IndexResourceRequest(
            url: url,
            resourceId: resourceId,
            languageRawValue: language.rawValue,
            timestamp: skipDecision.timestamp,
            content: skipDecision.content,
            contentHash: skipDecision.contentHash,
            language: language
        )
        try await upsertResourceAndIndexSymbols(request)
    }

    private func indexFromDisk(
        url: URL,
        resourceId: String,
        language: CodeLanguage,
        timestamp: Double?
    ) async throws {
        await IndexLogger.shared.log(
            "IndexerActor: Indexing \(url.lastPathComponent) (Language: \(language.rawValue))"
        )

        let resolvedTimestamp = timestamp ?? Date().timeIntervalSince1970
        let content = try String(contentsOf: url, encoding: .utf8)
        let contentHash = computeHash(for: content)

        let request = IndexResourceRequest(
            url: url,
            resourceId: resourceId,
            languageRawValue: language.rawValue,
            timestamp: resolvedTimestamp,
            content: content,
            contentHash: contentHash,
            language: language
        )
        try await upsertResourceAndIndexSymbols(request)
    }

    private func fileModificationTime(at url: URL) -> Double? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970
    }

    private struct SkipDecision {
        let shouldSkip: Bool
        let timestamp: Double
        let content: String
        let contentHash: String
    }

    private func shouldSkipIndexing(
        url: URL,
        resourceId: String,
        fileModTime: Double?
    ) async throws -> SkipDecision? {
        guard let fileModTime else { return nil }
        let existingModTime = try? await database.getResourceLastModified(resourceId: resourceId)
        guard let existingModTime else { return nil }
        guard abs(existingModTime - fileModTime) < 0.000_001 else { return nil }

        let content = try String(contentsOf: url, encoding: .utf8)
        let currentHash = computeHash(for: content)
        let existingHash = (try? await database.getResourceContentHash(resourceId: resourceId)) ?? nil

        if let existingHash, !existingHash.isEmpty, existingHash == currentHash {
            return SkipDecision(shouldSkip: true, timestamp: fileModTime, content: content, contentHash: currentHash)
        }

        return SkipDecision(shouldSkip: false, timestamp: fileModTime, content: content, contentHash: currentHash)
    }

    private func upsertResourceAndIndexSymbols(_ request: IndexResourceRequest) async throws {
        try await database.upsertResourceAndFTS(
            UpsertResourceAndFTSRequest(
                resourceId: request.resourceId,
                path: request.url.path,
                language: request.languageRawValue,
                timestamp: request.timestamp,
                contentHash: request.contentHash,
                content: request.content
            )
        )

        let symbols = await extractSymbols(content: request.content, resourceId: request.resourceId, language: request.language)
        try await storeSymbolsIfNeeded(symbols, resourceId: request.resourceId, fileName: request.url.lastPathComponent)
    }

    private func extractSymbols(content: String, resourceId: String, language: CodeLanguage) async -> [Symbol] {
        guard let module = await LanguageModuleManager.shared.getModule(for: language) else {
            return []
        }
        return module.symbolExtractor.extractSymbols(content: content, resourceId: resourceId)
    }

    private func storeSymbolsIfNeeded(_ symbols: [Symbol], resourceId: String, fileName: String) async throws {
        guard !symbols.isEmpty else { return }
        await IndexLogger.shared.log(
            "IndexerActor: Extracted \(symbols.count) symbols from \(fileName)"
        )
        try await database.deleteSymbols(for: resourceId)
        try await database.saveSymbolsBatched(symbols)
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
