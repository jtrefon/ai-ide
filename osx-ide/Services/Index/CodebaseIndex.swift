//
//  CodebaseIndex.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation
import Combine
import SQLite3

@MainActor
public protocol CodebaseIndexProtocol: Sendable {
    func start()
    func stop()

    func setEnabled(_ enabled: Bool)
    func reindexProject()
    func reindexProject(aiEnrichmentEnabled: Bool)
    func runAIEnrichment()

    func listIndexedFiles(matching query: String?, limit: Int, offset: Int) async throws -> [String]
    func findIndexedFiles(query: String, limit: Int) async throws -> [IndexedFileMatch]
    func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String
    func searchIndexedText(pattern: String, limit: Int) async throws -> [String]

    func searchSymbols(nameLike query: String, limit: Int) async throws -> [Symbol]
    func searchSymbolsWithPaths(nameLike query: String, limit: Int) async throws -> [SymbolSearchResult]
    func getSummaries(projectRoot: URL, limit: Int) async throws -> [(path: String, summary: String)]
    func getMemories(tier: MemoryTier?) async throws -> [MemoryEntry]
    func getStats() async throws -> IndexStats
}

@MainActor
public extension CodebaseIndexProtocol {
    func listIndexedFilesResult(matching query: String?, limit: Int, offset: Int) async -> Result<[String], AppError> {
        do {
            return .success(try await listIndexedFiles(matching: query, limit: limit, offset: offset))
        } catch {
            return .failure(mapToAppError(error, context: "listIndexedFiles"))
        }
    }

    func findIndexedFilesResult(query: String, limit: Int) async -> Result<[IndexedFileMatch], AppError> {
        do {
            return .success(try await findIndexedFiles(query: query, limit: limit))
        } catch {
            return .failure(mapToAppError(error, context: "findIndexedFiles"))
        }
    }

    func readIndexedFileResult(path: String, startLine: Int?, endLine: Int?) -> Result<String, AppError> {
        do {
            return .success(try readIndexedFile(path: path, startLine: startLine, endLine: endLine))
        } catch {
            return .failure(mapToAppError(error, context: "readIndexedFile"))
        }
    }

    func searchIndexedTextResult(pattern: String, limit: Int) async -> Result<[String], AppError> {
        do {
            return .success(try await searchIndexedText(pattern: pattern, limit: limit))
        } catch {
            return .failure(mapToAppError(error, context: "searchIndexedText"))
        }
    }

    func searchSymbolsResult(nameLike query: String, limit: Int) async -> Result<[Symbol], AppError> {
        do {
            return .success(try await searchSymbols(nameLike: query, limit: limit))
        } catch {
            return .failure(mapToAppError(error, context: "searchSymbols"))
        }
    }

    func searchSymbolsWithPathsResult(nameLike query: String, limit: Int) async -> Result<[SymbolSearchResult], AppError> {
        do {
            return .success(try await searchSymbolsWithPaths(nameLike: query, limit: limit))
        } catch {
            return .failure(mapToAppError(error, context: "searchSymbolsWithPaths"))
        }
    }

    func getSummariesResult(projectRoot: URL, limit: Int) async -> Result<[(path: String, summary: String)], AppError> {
        do {
            return .success(try await getSummaries(projectRoot: projectRoot, limit: limit))
        } catch {
            return .failure(mapToAppError(error, context: "getSummaries"))
        }
    }

    func getMemoriesResult(tier: MemoryTier?) async -> Result<[MemoryEntry], AppError> {
        do {
            return .success(try await getMemories(tier: tier))
        } catch {
            return .failure(mapToAppError(error, context: "getMemories"))
        }
    }

    func getStatsResult() async -> Result<IndexStats, AppError> {
        do {
            return .success(try await getStats())
        } catch {
            return .failure(mapToAppError(error, context: "getStats"))
        }
    }

    private func mapToAppError(_ error: Error, context: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .unknown("CodebaseIndex.\(context) failed: \(error.localizedDescription)")
    }
}

@MainActor
public class CodebaseIndex: CodebaseIndexProtocol, @unchecked Sendable {
    private let eventBus: EventBusProtocol
    private let coordinator: IndexCoordinator
    private let database: DatabaseStore
    private let indexer: IndexerActor
    private let memoryManager: MemoryManager
    private let queryService: QueryService
    private let aiService: AIService
    private let dbPath: String
    private let projectRoot: URL
    private let excludePatterns: [String]
    private var isEnabled: Bool
    private var aiEnrichmentAfterIndexCancellable: AnyCancellable?
    private var aiEnrichmentTask: Task<Void, Never>?
    
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
        
        self.database = try DatabaseStore(path: dbPath)
        self.indexer = IndexerActor(database: database, config: resolvedConfig)
        self.memoryManager = MemoryManager(database: database, eventBus: eventBus)
        self.queryService = QueryService(database: database)
        self.coordinator = IndexCoordinator(eventBus: eventBus, indexer: indexer, config: resolvedConfig, projectRoot: projectRoot)
    }

    public func listIndexedFiles(matching query: String?, limit: Int = 50, offset: Int = 0) async throws -> [String] {
        let absPaths = try await database.listResourcePaths(matching: query, limit: limit, offset: offset)
        return absPaths.map { absPath in
            if absPath.hasPrefix(projectRoot.path + "/") {
                return String(absPath.dropFirst(projectRoot.path.count + 1))
            }
            return absPath
        }
    }

    public func findIndexedFiles(query: String, limit: Int = 50) async throws -> [IndexedFileMatch] {
        let raw = try await database.findResourceMatches(query: query, limit: max(1, min(500, limit)))
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
        let needle = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return [] }

        let boundedLimit = max(1, min(500, limit))

        func relPath(_ absPath: String) -> String {
            if absPath.hasPrefix(projectRoot.path + "/") {
                return String(absPath.dropFirst(projectRoot.path.count + 1))
            }
            return absPath
        }

        // Candidate narrowing via FTS: split into identifier-like tokens and search those.
        // If we can't produce a meaningful token query (e.g. mostly punctuation), fall back
        // to scanning a bounded number of indexed files.
        let tokens = needle
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map(String.init)
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }

        let ftsQuery = tokens.prefix(3).joined(separator: " AND ")
        let maxCandidateFiles = min(800, max(50, boundedLimit * 20))

        let candidatePaths: [String]
        if !ftsQuery.isEmpty {
            candidatePaths = (try? await database.candidatePathsForFTS(query: ftsQuery, limit: maxCandidateFiles)) ?? []
        } else {
            candidatePaths = (try? await database.listResourcePaths(matching: nil, limit: maxCandidateFiles, offset: 0)) ?? []
        }

        if candidatePaths.isEmpty { return [] }

        var output: [String] = []
        output.reserveCapacity(min(boundedLimit, 50))

        for absPath in candidatePaths {
            if output.count >= boundedLimit { break }

            let fileURL = URL(fileURLWithPath: absPath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            // Stream-ish scan line-by-line to get true line numbers without expensive indexing.
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                if output.count >= boundedLimit { break }
                guard line.contains(needle) else { continue }

                let lineNo = idx + 1
                let snippetMax = 240
                let snippet = line.count > snippetMax ? String(line.prefix(snippetMax)) + "…" : line
                output.append("\(relPath(absPath)):\(lineNo): \(snippet)")
            }
        }

        return output
    }

    public convenience init(eventBus: EventBusProtocol) throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        try self.init(eventBus: eventBus, projectRoot: root, aiService: OpenRouterAIService())
    }
    
    public func start() {
        print("CodebaseIndex service started")
    }

    public func stop() {
        isEnabled = false
        aiEnrichmentAfterIndexCancellable?.cancel()
        aiEnrichmentAfterIndexCancellable = nil
        aiEnrichmentTask?.cancel()
        aiEnrichmentTask = nil
        coordinator.stop()
        Task { await database.shutdown() }
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
            aiEnrichmentAfterIndexCancellable = eventBus.subscribe(to: ProjectReindexCompletedEvent.self) { [weak self] _ in
                guard let self else { return }
                self.aiEnrichmentAfterIndexCancellable?.cancel()
                self.aiEnrichmentAfterIndexCancellable = nil
                self.runAIEnrichment()
            }
        }
    }

    public func runAIEnrichment() {
        guard isEnabled else { 
            Task { @MainActor in await IndexLogger.shared.log("AI Enrichment skipped: Indexing is disabled") }
            return 
        }

        aiEnrichmentTask?.cancel()
        aiEnrichmentTask = Task { @MainActor in
            let scoringEngine = QualityScoringEngine(projectRoot: projectRoot, scorers: [SwiftHeuristicScorer()])
            let start = Date()
            await IndexLogger.shared.log("AI Enrichment started")
            await eventBus.publish(AIEnrichmentStartedEvent())

            let files = IndexCoordinator.enumerateProjectFiles(rootURL: projectRoot, excludePatterns: excludePatterns)
                .filter { Self.isAIEnrichableFile($0) }
            let total = files.count
            await IndexLogger.shared.log("Found \(total) files for AI enrichment")

            var processed = 0
            for file in files {
                if Task.isCancelled { break }
                if !isEnabled { 
                    await IndexLogger.shared.log("AI Enrichment aborted: Indexing disabled during process")
                    break 
                }
                
                await IndexLogger.shared.log("Enriching file \(processed + 1)/\(total): \(file.lastPathComponent)")
                await eventBus.publish(AIEnrichmentProgressEvent(processedCount: processed, totalCount: total, currentFile: file))

                let fileModTime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970

                let existingModTime = try? await database.getResourceLastModified(resourceId: file.absoluteString)

                if let fileModTime,
                   let existingModTime,
                   abs(existingModTime - fileModTime) < 0.000_001,
                   (try? await database.isResourceAIEnriched(resourceId: file.absoluteString)) == true {
                    await IndexLogger.shared.log("Skipping \(file.lastPathComponent) (already enriched)")
                    processed += 1
                    await eventBus.publish(AIEnrichmentProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
                    continue
                }

                do {
                    let content = try String(contentsOf: file, encoding: .utf8)

                    // Heuristic scoring first (deterministic, traceable; does not depend on AI model).
                    // Persist score + details so the UI "Q" metric is always meaningful.
                    let language = LanguageDetector.detect(at: file)
                    let relPath: String
                    if file.path.hasPrefix(self.projectRoot.path + "/") {
                        relPath = String(file.path.dropFirst(self.projectRoot.path.count + 1))
                    } else {
                        relPath = file.path
                    }

                    let assessment = await scoringEngine.score(language: language, path: relPath, content: content)
                    let heuristicScore = max(0, min(100, assessment.score))

                    do {
                        let jsonData = try JSONEncoder().encode(assessment)
                        let json = String(data: jsonData, encoding: .utf8)
                        try await database.updateQualityScore(resourceId: file.absoluteString, score: heuristicScore)
                        try await database.updateQualityDetails(resourceId: file.absoluteString, details: json)
                        await IndexLogger.shared.log("QualityScore: \(String(format: "%.0f", heuristicScore)) for \(relPath)")
                    } catch {
                        await IndexLogger.shared.log("QualityScore: Failed to persist quality details for \(relPath): \(error)")
                    }

                    let prompt = Self.makeEnrichmentPrompt(path: file.path, content: content)

                    // Use a timeout for the AI call to prevent getting stuck
                    let response = try await withTimeout(seconds: 45) {
                        try await self.aiService.sendMessage(prompt, context: nil, tools: nil, mode: nil, projectRoot: self.projectRoot)
                    }
                    
                    let result = Self.parseEnrichmentResponse(from: response.content)
                    let score = result?.score ?? 0
                    let summary = result?.summary
                    
                    await IndexLogger.shared.log("IndexerActor: AI suggested score \(score) for \(file.lastPathComponent)")
                    
                    try await database.markAIEnriched(resourceId: file.absoluteString, score: Double(score), summary: summary)
                    await IndexLogger.shared.log("Successfully enriched \(file.lastPathComponent) (Score: \(score))")
                } catch {
                    await IndexLogger.shared.log("Failed to enrich \(file.lastPathComponent): \(error)")
                }

                processed += 1
                await eventBus.publish(AIEnrichmentProgressEvent(processedCount: processed, totalCount: total, currentFile: file))
            }

            if Task.isCancelled { return }

            let duration = Date().timeIntervalSince(start)
            await IndexLogger.shared.log("AI Enrichment completed in \(String(format: "%.2f", duration))s")
            await eventBus.publish(AIEnrichmentCompletedEvent(processedCount: processed, duration: duration))
        }
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AppError.aiServiceError("AI request timed out after \(seconds)s")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    public func searchSymbols(nameLike query: String, limit: Int = 50) async throws -> [Symbol] {
        try await queryService.searchSymbols(nameLike: query, limit: limit)
    }

    public func searchSymbolsWithPaths(nameLike query: String, limit: Int = 50) async throws -> [SymbolSearchResult] {
        try await queryService.searchSymbolsWithPaths(nameLike: query, limit: limit)
    }

    public func getSummaries(projectRoot: URL, limit: Int = 20) async throws -> [(path: String, summary: String)] {
        try await database.getAIEnrichedSummaries(projectRoot: projectRoot, limit: limit)
    }

    public func getMemories(tier: MemoryTier? = nil) async throws -> [MemoryEntry] {
        try await queryService.getMemories(tier: tier)
    }

    public func getStats() async throws -> IndexStats {
        let counts = try await database.getIndexStatsCounts()
        let totalProjectFileCount = IndexCoordinator.enumerateProjectFiles(rootURL: projectRoot, excludePatterns: excludePatterns).count

        let aiEnrichableProjectFileCount = IndexCoordinator
            .enumerateProjectFiles(rootURL: projectRoot, excludePatterns: excludePatterns)
            .filter { Self.isAIEnrichableFile($0) }
            .count

        let allowed = AppConstants.Indexing.allowedExtensions
        let scopedIndexedCount = (try? await database.getIndexedResourceCountScoped(projectRoot: projectRoot, allowedExtensions: allowed)) ?? counts.indexedResourceCount

        let scopedAIEnrichedCount = (try? await database.getAIEnrichedResourceCountScoped(projectRoot: projectRoot, allowedExtensions: allowed)) ?? 0
        let avgAIQuality = (try? await database.getAverageAIQualityScoreScoped(projectRoot: projectRoot, allowedExtensions: allowed)) ?? 0

        let kindCounts = try await database.getSymbolKindCounts()
        let avgQuality = try await database.getAverageQualityScore()
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
            aiEnrichableProjectFileCount: aiEnrichableProjectFileCount,
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

    private static func makeEnrichmentPrompt(path: String, content: String) -> String {
        return """
        Analyze the following source file and provide a quality score and a concise summary.
        
        The summary should be 1-2 sentences describing the main purpose of the file or the primary class/struct it contains. 
        Focus on "what" and "why", not just "how".
        
        Return ONLY a single line JSON object like: 
        {"score": 85, "summary": "Manages the SQLite database for the codebase index, handling table creation and thread-safe operations."}
        
        Where score is an integer from 0 to 100.
        
        File: \(path)
        
        Code:
        \(content)
        """
    }

    private static func parseEnrichmentResponse(from content: String?) -> (score: Int, summary: String?)? {
        guard let content else { return nil }
        guard let data = content.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        let score: Int
        if let s = obj["score"] as? Int { 
            score = max(0, min(100, s)) 
        } else if let s = obj["score"] as? Double {
            score = max(0, min(100, Int(s.rounded())))
        } else {
            score = 0
        }
        
        let summary = obj["summary"] as? String
        return (score, summary)
    }

    private static func isIndexableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        return AppConstants.Indexing.allowedExtensions.contains(ext)
    }

    private static func isAIEnrichableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return false }
        return AppConstants.Indexing.aiEnrichableExtensions.contains(ext)
    }

    static func resolveIndexDirectory(projectRoot: URL) -> URL {
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

    static func indexDatabaseURL(projectRoot: URL) -> URL {
        let dir = resolveIndexDirectory(projectRoot: projectRoot)
        return dir.appendingPathComponent("codebase.sqlite")
    }
}
