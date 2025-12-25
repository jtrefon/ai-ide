//
//  CodebaseIndex.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation
import Combine

@MainActor
public protocol CodebaseIndexProtocol: Sendable {
    func start()

    func setEnabled(_ enabled: Bool)
    func reindexProject()
    func reindexProject(aiEnrichmentEnabled: Bool)
    func runAIEnrichment()

    func listIndexedFiles(matching query: String?, limit: Int, offset: Int) throws -> [String]
    func findIndexedFiles(query: String, limit: Int) throws -> [IndexedFileMatch]
    func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String
    func searchIndexedText(pattern: String, limit: Int) async throws -> [String]

    func searchSymbols(nameLike query: String, limit: Int) throws -> [Symbol]
    func getMemories(tier: MemoryTier?) throws -> [MemoryEntry]
    func getStats() throws -> IndexStats
}

@MainActor
public class CodebaseIndex: CodebaseIndexProtocol, @unchecked Sendable {
    private let eventBus: EventBusProtocol
    private let coordinator: IndexCoordinator
    private let databaseManager: DatabaseManager
    private let indexer: IndexerActor
    private let memoryManager: MemoryManager
    private let queryService: QueryService
    private let aiService: AIService
    private let dbPath: String
    private let projectRoot: URL
    private let excludePatterns: [String]
    private var isEnabled: Bool
    private var aiEnrichmentAfterIndexCancellable: AnyCancellable?
    
    init(eventBus: EventBusProtocol, projectRoot: URL, aiService: AIService, config: IndexConfiguration = .default) throws {
        self.eventBus = eventBus
        self.projectRoot = projectRoot
        self.aiService = aiService
        let resolvedExcludePatterns = IndexCoordinator.loadExcludePatterns(projectRoot: projectRoot, defaultPatterns: config.excludePatterns)
        let resolvedConfig = IndexConfiguration(enabled: config.enabled, debounceMs: config.debounceMs, excludePatterns: resolvedExcludePatterns)

        self.excludePatterns = resolvedExcludePatterns
        self.isEnabled = resolvedConfig.enabled

        let resolved = Self.resolveIndexDirectory(projectRoot: projectRoot)
        self.dbPath = resolved.appendingPathComponent("codebase.sqlite").path
        
        self.databaseManager = try DatabaseManager(path: dbPath)
        self.indexer = IndexerActor(database: databaseManager, config: resolvedConfig)
        self.memoryManager = MemoryManager(database: databaseManager, eventBus: eventBus)
        self.queryService = QueryService(database: databaseManager)
        self.coordinator = IndexCoordinator(eventBus: eventBus, indexer: indexer, config: resolvedConfig)
    }

    public func listIndexedFiles(matching query: String?, limit: Int = 50, offset: Int = 0) throws -> [String] {
        let absPaths = try databaseManager.listResourcePaths(matching: query, limit: limit, offset: offset)
        return absPaths.map { absPath in
            if absPath.hasPrefix(projectRoot.path + "/") {
                return String(absPath.dropFirst(projectRoot.path.count + 1))
            }
            return absPath
        }
    }

    public func findIndexedFiles(query: String, limit: Int = 50) throws -> [IndexedFileMatch] {
        let raw = try databaseManager.findResourceMatches(query: query, limit: max(1, min(500, limit)))
        if raw.isEmpty { return [] }

        func relPath(_ absPath: String) -> String {
            if absPath.hasPrefix(projectRoot.path + "/") {
                return String(absPath.dropFirst(projectRoot.path.count + 1))
            }
            return absPath
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func score(for absPath: String, aiEnriched: Bool, qualityScore: Double?) -> Double {
            let rel = relPath(absPath)
            let lowerRel = rel.lowercased()
            let base = URL(fileURLWithPath: rel).lastPathComponent.lowercased()

            var s: Double = 0

            if base == needle { s += 1000 }
            if base.hasPrefix(needle) { s += 700 }
            if base.contains(needle) { s += 500 }

            if lowerRel == needle { s += 400 }
            if lowerRel.hasPrefix(needle) { s += 250 }
            if lowerRel.contains(needle) { s += 100 }

            // Prefer code over docs when ambiguous.
            if lowerRel.hasSuffix(".md") || lowerRel.hasSuffix(".markdown") { s -= 50 }

            if aiEnriched { s += 25 }
            if let qualityScore { s += qualityScore }

            return s
        }

        let sorted = raw.sorted { a, b in
            let sa = score(for: a.path, aiEnriched: a.aiEnriched, qualityScore: a.qualityScore)
            let sb = score(for: b.path, aiEnriched: b.aiEnriched, qualityScore: b.qualityScore)
            if sa != sb { return sa > sb }
            return relPath(a.path) < relPath(b.path)
        }

        return sorted.map { m in
            IndexedFileMatch(path: relPath(m.path), aiEnriched: m.aiEnriched, qualityScore: m.qualityScore)
        }
    }

    public func readIndexedFile(path: String, startLine: Int? = nil, endLine: Int? = nil) throws -> String {
        let relative = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relative.isEmpty else {
            throw AppError.aiServiceError("Missing 'path' argument")
        }

        let fileURL: URL
        if relative.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: relative)
        } else {
            fileURL = projectRoot.appendingPathComponent(relative)
        }

        let standardizedFileURL = fileURL.standardizedFileURL
        let standardizedProjectRoot = projectRoot.standardizedFileURL
        if !standardizedFileURL.path.hasPrefix(standardizedProjectRoot.path + "/") {
            throw AppError.permissionDenied("index_read_file may only read files within the project root")
        }

        let absPath = standardizedFileURL.path
        let existsOnDisk = FileManager.default.fileExists(atPath: absPath)
        let isInIndex = (try? databaseManager.hasResourcePath(absPath)) == true

        if !existsOnDisk {
            throw AppError.fileNotFound(relative)
        }

        let content = try String(contentsOf: standardizedFileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let total = lines.count

        let start = max(1, startLine ?? 1)
        let end = min(total, endLine ?? total)
        if start > end {
            return ""
        }

        var output: [String] = []
        output.reserveCapacity(end - start + 1)
        for i in start...end {
            let text = lines[i - 1]
            output.append(String(format: "%6d | %@", i, text))
        }

        return output.joined(separator: "\n")
    }

    public func searchIndexedText(pattern: String, limit: Int = 100) async throws -> [String] {
        let needle = pattern
        if needle.isEmpty { return [] }

        var matches: [String] = []
        matches.reserveCapacity(min(limit, 100))

        var offset = 0
        let pageSize = 200

        while matches.count < limit {
            let batch = try databaseManager.listResourcePaths(matching: nil, limit: pageSize, offset: offset)
            if batch.isEmpty { break }
            offset += batch.count

            for absPath in batch {
                if matches.count >= limit { break }
                do {
                    let url = URL(fileURLWithPath: absPath)
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let lines = content.components(separatedBy: .newlines)
                    for (idx, line) in lines.enumerated() {
                        if line.contains(needle) {
                            let rel: String
                            if absPath.hasPrefix(projectRoot.path + "/") {
                                rel = String(absPath.dropFirst(projectRoot.path.count + 1))
                            } else {
                                rel = absPath
                            }
                            let snippet = line.trimmingCharacters(in: .whitespaces)
                            matches.append("\(rel):\(idx + 1): \(snippet)")
                            if matches.count >= limit { break }
                        }
                    }
                } catch {
                    continue
                }
            }
        }

        return matches
    }

    public convenience init(eventBus: EventBusProtocol) throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        try self.init(eventBus: eventBus, projectRoot: root, aiService: OpenRouterAIService())
    }
    
    public func start() {
        print("CodebaseIndex service started")
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        coordinator.setEnabled(enabled)
    }

    public func reindexProject() {
        reindexProject(aiEnrichmentEnabled: false)
    }

    public func reindexProject(aiEnrichmentEnabled: Bool) {
        guard isEnabled else { return }
        coordinator.reindexProject(rootURL: projectRoot)

        if aiEnrichmentEnabled {
            aiEnrichmentAfterIndexCancellable?.cancel()
            aiEnrichmentAfterIndexCancellable = eventBus.subscribe(to: IndexingCompletedEvent.self) { [weak self] _ in
                guard let self else { return }
                self.aiEnrichmentAfterIndexCancellable?.cancel()
                self.aiEnrichmentAfterIndexCancellable = nil
                self.runAIEnrichment()
            }
        }
    }

    public func runAIEnrichment() {
        guard isEnabled else { return }

        Task {
            let start = Date()
            eventBus.publish(AIEnrichmentStartedEvent())

            let files = IndexCoordinator.enumerateProjectFiles(rootURL: projectRoot, excludePatterns: excludePatterns)
                .filter { Self.isAIEnrichableFile($0) }
            let total = files.count

            var processed = 0
            for file in files {
                if !isEnabled { break }
                eventBus.publish(AIEnrichmentProgressEvent(processedCount: processed, totalCount: total, currentFile: file))

                let fileModTime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970

                let existingModTime: Double? = (try? databaseManager.getResourceLastModified(resourceId: file.absoluteString)) ?? nil

                if let fileModTime,
                   let existingModTime,
                   abs(existingModTime - fileModTime) < 0.000_001,
                   (try? databaseManager.isResourceAIEnriched(resourceId: file.absoluteString)) == true {
                    processed += 1
                    eventBus.publish(AIEnrichmentProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
                    continue
                }

                do {
                    let content = try String(contentsOf: file, encoding: .utf8)
                    let prompt = Self.makeQualityPrompt(path: file.path, content: content)
                    let response = try await aiService.sendMessage(prompt, context: nil, tools: nil, mode: nil, projectRoot: projectRoot)
                    let score = Self.parseScore(from: response.content) ?? 0
                    try databaseManager.markAIEnriched(resourceId: file.absoluteString, score: Double(score))
                } catch {
                    // If enrichment fails for a file, continue; progress still advances.
                }

                processed += 1
                eventBus.publish(AIEnrichmentProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
            }

            let duration = Date().timeIntervalSince(start)
            eventBus.publish(AIEnrichmentCompletedEvent(processedCount: processed, duration: duration))
        }
    }

    public func searchSymbols(nameLike query: String, limit: Int = 50) throws -> [Symbol] {
        try queryService.searchSymbols(nameLike: query, limit: limit)
    }

    public func getMemories(tier: MemoryTier? = nil) throws -> [MemoryEntry] {
        try queryService.getMemories(tier: tier)
    }

    public func getStats() throws -> IndexStats {
        let counts = try databaseManager.getIndexStatsCounts()
        let totalProjectFileCount = IndexCoordinator.enumerateProjectFiles(rootURL: projectRoot, excludePatterns: excludePatterns).count

        let allowed: Set<String> = [
            "swift", "js", "ts", "py", "html", "css", "json", "yaml", "yml", "md", "markdown"
        ]
        let scopedIndexedCount = (try? databaseManager.getIndexedResourceCountScoped(projectRoot: projectRoot, allowedExtensions: allowed)) ?? counts.indexedResourceCount

        let scopedAIEnrichedCount = (try? databaseManager.getAIEnrichedResourceCountScoped(projectRoot: projectRoot, allowedExtensions: allowed)) ?? 0
        let avgAIQuality = (try? databaseManager.getAverageAIQualityScoreScoped(projectRoot: projectRoot, allowedExtensions: allowed)) ?? 0

        let kindCounts = try databaseManager.getSymbolKindCounts()
        let avgQuality = try databaseManager.getAverageQualityScore()
        let sizeBytes: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
            sizeBytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            sizeBytes = 0
        }

        let workspaceIndexDir = projectRoot.appendingPathComponent(".ide").appendingPathComponent("index")
        let dbURL = URL(fileURLWithPath: dbPath)
        let isInWorkspace = dbURL.path.hasPrefix(workspaceIndexDir.path)

        let classCount = kindCounts[SymbolKind.class.rawValue] ?? 0
        let structCount = kindCounts[SymbolKind.struct.rawValue] ?? 0
        let enumCount = kindCounts[SymbolKind.enum.rawValue] ?? 0
        let protocolCount = kindCounts[SymbolKind.protocol.rawValue] ?? 0
        let functionCount = kindCounts[SymbolKind.function.rawValue] ?? 0
        let variableCount = kindCounts[SymbolKind.variable.rawValue] ?? 0

        return IndexStats(
            indexedResourceCount: scopedIndexedCount,
            aiEnrichedResourceCount: scopedAIEnrichedCount,
            totalProjectFileCount: totalProjectFileCount,
            symbolCount: counts.symbolCount,
            classCount: classCount,
            structCount: structCount,
            enumCount: enumCount,
            protocolCount: protocolCount,
            functionCount: functionCount,
            variableCount: variableCount,
            memoryCount: counts.memoryCount,
            longTermMemoryCount: counts.longTermMemoryCount,
            databaseSizeBytes: sizeBytes,
            databasePath: dbPath,
            isDatabaseInWorkspace: isInWorkspace,
            averageQualityScore: avgQuality,
            averageAIQualityScore: avgAIQuality
        )
    }

    private static func makeQualityPrompt(path: String, content: String) -> String {
        return """
You are grading a source file for code quality.

Return ONLY a single line JSON object like: {"score": 0}
Where score is an integer from 0 to 100.

File: \(path)

Code:
\(content)
"""
    }

    private static func parseScore(from content: String?) -> Int? {
        guard let content else { return nil }
        guard let data = content.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let score = obj["score"] as? Int { return max(0, min(100, score)) }
        if let score = obj["score"] as? Double { return max(0, min(100, Int(score.rounded()))) }
        return nil
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

    private static func isAIEnrichableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        let allowed: Set<String> = [
            "swift",
            "js", "jsx",
            "ts", "tsx",
            "py",
            "html", "css"
        ]
        return allowed.contains(ext)
    }

    private static func resolveIndexDirectory(projectRoot: URL) -> URL {
        let fileManager = FileManager.default
        let ideDir = projectRoot.appendingPathComponent(".ide")
        let indexDir = ideDir.appendingPathComponent("index")

        do {
            try fileManager.createDirectory(at: indexDir, withIntermediateDirectories: true)
            return indexDir
        } catch {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let fallbackRoot = (appSupport ?? fileManager.temporaryDirectory)
                .appendingPathComponent("osx-ide")
                .appendingPathComponent("index")
                .appendingPathComponent(String(projectRoot.path.hashValue))

            try? fileManager.createDirectory(at: fallbackRoot, withIntermediateDirectories: true)
            return fallbackRoot
        }
    }
}
