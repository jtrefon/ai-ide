//
//  CodebaseIndex.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

@MainActor
public protocol CodebaseIndexProtocol {
    func start()

    func setEnabled(_ enabled: Bool)
    func reindexProject()
    func reindexProject(aiEnrichmentEnabled: Bool)
    func runAIEnrichment()

    func searchSymbols(nameLike query: String, limit: Int) throws -> [Symbol]
    func getMemories(tier: MemoryTier?) throws -> [MemoryEntry]
    func getStats() throws -> IndexStats
}

@MainActor
public class CodebaseIndex: CodebaseIndexProtocol {
    private let eventBus: EventBusProtocol
    private let coordinator: IndexCoordinator
    private let databaseManager: DatabaseManager
    private let indexer: IndexerActor
    private let memoryManager: MemoryManager
    private let queryService: QueryService
    private let aiService: AIService
    private let dbPath: String
    private let projectRoot: URL
    private var isEnabled: Bool
    
    init(eventBus: EventBusProtocol, projectRoot: URL, aiService: AIService, config: IndexConfiguration = .default) throws {
        self.eventBus = eventBus
        self.projectRoot = projectRoot
        self.aiService = aiService
        self.isEnabled = config.enabled

        let resolved = Self.resolveIndexDirectory(projectRoot: projectRoot)
        self.dbPath = resolved.appendingPathComponent("codebase.sqlite").path
        
        self.databaseManager = try DatabaseManager(path: dbPath)
        self.indexer = IndexerActor(database: databaseManager, config: config)
        self.memoryManager = MemoryManager(database: databaseManager, eventBus: eventBus)
        self.queryService = QueryService(database: databaseManager)
        self.coordinator = IndexCoordinator(eventBus: eventBus, indexer: indexer, config: config)
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
            runAIEnrichment()
        }
    }

    public func runAIEnrichment() {
        guard isEnabled else { return }

        Task {
            let start = Date()
            eventBus.publish(AIEnrichmentStartedEvent())

            let files = IndexCoordinator.enumerateProjectFiles(rootURL: projectRoot, excludePatterns: [])
                .filter { Self.isAIEnrichableFile($0) }
            let total = files.count

            var processed = 0
            for file in files {
                if !isEnabled { break }
                eventBus.publish(AIEnrichmentProgressEvent(processedCount: processed, totalCount: total, currentFile: file))

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
        let totalProjectFileCount = Self.computeTotalProjectFileCount(projectRoot: projectRoot)

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

    private static func computeTotalProjectFileCount(projectRoot: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".ide" {
                enumerator.skipDescendants()
                continue
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory {
                if Self.isIndexableFile(url) {
                    count += 1
                }
            }
        }
        return count
    }

    private static func isIndexableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        let allowed: Set<String> = [
            "swift", "js", "ts", "py", "html", "css", "json", "yaml", "yml", "md", "markdown"
        ]
        return allowed.contains(ext)
    }

    private static func isAIEnrichableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        let allowed: Set<String> = [
            "swift", "js", "ts", "py", "html", "css"
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
