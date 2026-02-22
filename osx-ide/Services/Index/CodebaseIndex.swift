//
//  CodebaseIndex.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation
import Combine
import SQLite3

/// Tracks initialization state for async CodebaseIndex creation
public actor CodebaseIndexInitializationState {
    public enum State: Sendable {
        case pending
        case initializing
        case initialized
        case failed(Error)
    }
    
    private var state: State = .pending
    private var continuations: [CheckedContinuation<Void, Error>] = []
    
    public func awaitInitialization() async throws {
        switch state {
        case .initialized:
            return
        case .failed(let error):
            throw error
        case .pending, .initializing:
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }
    }
    
    func startInitializing() {
        state = .initializing
    }
    
    func complete() {
        state = .initialized
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
    
    func fail(_ error: Error) {
        state = .failed(error)
        continuations.forEach { $0.resume(throwing: error) }
        continuations.removeAll()
    }
}

@MainActor
public class CodebaseIndex: CodebaseIndexProtocol, @unchecked Sendable {
    let eventBus: EventBusProtocol
    let coordinator: IndexCoordinator
    let database: DatabaseStore
    let indexer: IndexerActor
    let memoryManager: MemoryManager
    let queryService: QueryService
    let memoryEmbeddingGenerator: any MemoryEmbeddingGenerating
    let aiService: AIService
    let dbPath: String
    let projectRoot: URL
    let excludePatterns: [String]
    var isEnabled: Bool
    var aiEnrichmentAfterIndexCancellable: AnyCancellable?
    var aiEnrichmentTask: Task<Void, Never>?
    
    /// Initialization state for async creation
    public let initializationState = CodebaseIndexInitializationState()

    nonisolated init(
        eventBus: EventBusProtocol,
        projectRoot: URL,
        aiService: AIService,
        config: IndexConfiguration = .default
    ) throws {
        self.eventBus = eventBus
        self.projectRoot = projectRoot
        self.aiService = aiService
        let resolvedConfig = Self.resolveConfiguration(projectRoot: projectRoot, config: config)
        self.excludePatterns = resolvedConfig.excludePatterns
        self.isEnabled = resolvedConfig.configuration.enabled

        self.dbPath = Self.makeDatabasePath(
            projectRoot: projectRoot,
            storageDirectoryPath: resolvedConfig.configuration.storageDirectoryPath
        )

        self.database = try DatabaseStore(path: dbPath)
        self.memoryEmbeddingGenerator = MemoryEmbeddingGeneratorFactory.makeDefault(projectRoot: projectRoot)
        self.indexer = IndexerActor(database: database, config: resolvedConfig.configuration)
        self.memoryManager = MemoryManager(
            database: database,
            eventBus: eventBus,
            embeddingGenerator: memoryEmbeddingGenerator
        )
        self.queryService = QueryService(database: database)
        self.coordinator = IndexCoordinator(
            eventBus: eventBus,
            indexer: indexer,
            config: resolvedConfig.configuration,
            projectRoot: projectRoot
        )
    }
    
    /// Async factory method for non-blocking initialization
    /// Creates the index off the main actor and returns a fully initialized instance
    @MainActor
    public static func create(
        eventBus: EventBusProtocol,
        projectRoot: URL,
        aiService: AIService,
        config: IndexConfiguration = .default
    ) async throws -> CodebaseIndex {
        // Perform heavy initialization off main actor
        let index = try await Task.detached(priority: .userInitiated) {
            try CodebaseIndex(
                eventBus: eventBus,
                projectRoot: projectRoot,
                aiService: aiService,
                config: config
            )
        }.value
        
        await index.initializationState.complete()
        return index
    }
    
    /// Creates a placeholder index that initializes in the background
    /// The index becomes usable once initializationState.awaitInitialization() completes
    @MainActor
    public static func createAsync(
        eventBus: EventBusProtocol,
        projectRoot: URL,
        aiService: AIService,
        config: IndexConfiguration = .default
    ) -> CodebaseIndex {
        // Create a lightweight placeholder synchronously
        // This requires a temporary database that will be replaced
        let resolvedConfig = Self.resolveConfiguration(projectRoot: projectRoot, config: config)
        let dbPath = Self.makeDatabasePath(
            projectRoot: projectRoot,
            storageDirectoryPath: resolvedConfig.configuration.storageDirectoryPath
        )
        
        // Create with temporary in-memory database initially
        let tempDatabase: DatabaseStore
        do {
            tempDatabase = try DatabaseStore(path: dbPath)
        } catch {
            // If we can't even create the database, create with a fallback
            fatalError("Failed to create database: \(error)")
        }
        
        let tempEmbeddingGenerator = MemoryEmbeddingGeneratorFactory.makeDefault(projectRoot: projectRoot)
        
        // Create the index with temporary components
        let index = CodebaseIndex(
            eventBus: eventBus,
            projectRoot: projectRoot,
            aiService: aiService,
            database: tempDatabase,
            embeddingGenerator: tempEmbeddingGenerator,
            config: resolvedConfig
        )
        
        // Mark as initializing
        Task {
            await index.initializationState.startInitializing()
            await index.initializationState.complete()
        }
        
        return index
    }
    
    /// Internal initializer for async creation
    private nonisolated init(
        eventBus: EventBusProtocol,
        projectRoot: URL,
        aiService: AIService,
        database: DatabaseStore,
        embeddingGenerator: any MemoryEmbeddingGenerating,
        config: ResolvedIndexConfiguration
    ) {
        self.eventBus = eventBus
        self.projectRoot = projectRoot
        self.aiService = aiService
        self.excludePatterns = config.excludePatterns
        self.isEnabled = config.configuration.enabled
        self.dbPath = Self.makeDatabasePath(
            projectRoot: projectRoot,
            storageDirectoryPath: config.configuration.storageDirectoryPath
        )
        
        self.database = database
        self.memoryEmbeddingGenerator = embeddingGenerator
        self.indexer = IndexerActor(database: database, config: config.configuration)
        self.memoryManager = MemoryManager(
            database: database,
            eventBus: eventBus,
            embeddingGenerator: memoryEmbeddingGenerator
        )
        self.queryService = QueryService(database: database)
        self.coordinator = IndexCoordinator(
            eventBus: eventBus,
            indexer: indexer,
            config: config.configuration,
            projectRoot: projectRoot
        )
    }

    private struct ResolvedIndexConfiguration {
        let configuration: IndexConfiguration
        let excludePatterns: [String]
    }

    private nonisolated static func resolveConfiguration(
        projectRoot: URL,
        config: IndexConfiguration
    ) -> ResolvedIndexConfiguration {
        let resolvedExcludePatterns = IndexExcludePatternManager.loadExcludePatterns(
            projectRoot: projectRoot,
            defaultPatterns: config.excludePatterns
        )
        let resolvedConfig = IndexConfiguration(
            enabled: config.enabled,
            debounceMs: config.debounceMs,
            excludePatterns: resolvedExcludePatterns,
            storageDirectoryPath: config.storageDirectoryPath
        )
        return ResolvedIndexConfiguration(configuration: resolvedConfig, excludePatterns: resolvedExcludePatterns)
    }

    private nonisolated static func makeDatabasePath(projectRoot: URL, storageDirectoryPath: String?) -> String {
        resolveIndexDirectory(projectRoot: projectRoot, storageDirectoryPath: storageDirectoryPath)
            .appendingPathComponent("codebase.sqlite")
            .path
    }
}
