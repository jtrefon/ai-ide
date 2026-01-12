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
public class CodebaseIndex: CodebaseIndexProtocol, @unchecked Sendable {
    let eventBus: EventBusProtocol
    let coordinator: IndexCoordinator
    let database: DatabaseStore
    let indexer: IndexerActor
    let memoryManager: MemoryManager
    let queryService: QueryService
    let aiService: AIService
    let dbPath: String
    let projectRoot: URL
    let excludePatterns: [String]
    var isEnabled: Bool
    var aiEnrichmentAfterIndexCancellable: AnyCancellable?
    var aiEnrichmentTask: Task<Void, Never>?
    
    init(eventBus: EventBusProtocol, projectRoot: URL, aiService: AIService, config: IndexConfiguration = .default) throws {
        self.eventBus = eventBus
        self.projectRoot = projectRoot
        self.aiService = aiService
        let resolvedConfig = Self.resolveConfiguration(projectRoot: projectRoot, config: config)
        self.excludePatterns = resolvedConfig.excludePatterns
        self.isEnabled = resolvedConfig.configuration.enabled

        self.dbPath = Self.makeDatabasePath(projectRoot: projectRoot)

        self.database = try DatabaseStore(path: dbPath)
        self.indexer = IndexerActor(database: database, config: resolvedConfig.configuration)
        self.memoryManager = MemoryManager(database: database, eventBus: eventBus)
        self.queryService = QueryService(database: database)
        self.coordinator = IndexCoordinator(eventBus: eventBus, indexer: indexer, config: resolvedConfig.configuration, projectRoot: projectRoot)
    }

    private struct ResolvedIndexConfiguration {
        let configuration: IndexConfiguration
        let excludePatterns: [String]
    }

    private static func resolveConfiguration(projectRoot: URL, config: IndexConfiguration) -> ResolvedIndexConfiguration {
        let resolvedExcludePatterns = IndexExcludePatternManager.loadExcludePatterns(projectRoot: projectRoot, defaultPatterns: config.excludePatterns)
        let resolvedConfig = IndexConfiguration(enabled: config.enabled, debounceMs: config.debounceMs, excludePatterns: resolvedExcludePatterns)
        return ResolvedIndexConfiguration(configuration: resolvedConfig, excludePatterns: resolvedExcludePatterns)
    }

    private static func makeDatabasePath(projectRoot: URL) -> String {
        resolveIndexDirectory(projectRoot: projectRoot)
            .appendingPathComponent("codebase.sqlite")
            .path
    }
}
