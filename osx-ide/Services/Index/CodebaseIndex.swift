//
//  CodebaseIndex.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Combine
import Foundation
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
    private var continuation: CheckedContinuation<Void, Error>?

    public func awaitInitialization() async throws {
        switch state {
        case .initialized:
            return
        case .failed(let error):
            throw error
        case .pending, .initializing:
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    func startInitializing() {
        state = .initializing
    }

    func complete() {
        state = .initialized
        // Resume the continuation outside of actor isolation to prevent deadlock
        let cont = continuation
        continuation = nil
        cont?.resume()
    }

    func fail(_ error: Error) {
        state = .failed(error)
        // Resume the continuation outside of actor isolation to prevent deadlock
        let cont = continuation
        continuation = nil
        cont?.resume(throwing: error)
    }
}

public class CodebaseIndex: CodebaseIndexProtocol, @unchecked Sendable {
    let eventBus: EventBusProtocol
    let coordinator: IndexCoordinator
    let database: DatabaseStore
    let indexer: IndexerActor
    let memoryManager: MemoryManager
    let queryService: QueryService
    var memoryEmbeddingGenerator: any MemoryEmbeddingGenerating
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
        // CRITICAL: Use HashingMemoryEmbeddingGenerator for fast startup.
        // CoreML model loading can take MINUTES on first run (NPU compilation).
        // The async factory method will replace this with CoreML if available.
        self.memoryEmbeddingGenerator = HashingMemoryEmbeddingGenerator()
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
    /// This method avoids actor isolation contention by using the async createAsync pattern
    public static func create(
        eventBus: EventBusProtocol,
        projectRoot: URL,
        aiService: AIService,
        config: IndexConfiguration = .default
    ) async throws -> CodebaseIndex {
        let createStart = Date()
        Swift.print("[DIAG] CodebaseIndex.create START for: \(projectRoot.path)")

        // Use createAsync which creates the index synchronously but without blocking
        // This avoids the actor isolation contention that occurred with Task.detached + .value
        let index = CodebaseIndex.createAsync(
            eventBus: eventBus,
            projectRoot: projectRoot,
            aiService: aiService,
            config: config
        )

        Swift.print(
            "[DIAG] CodebaseIndex.create got index at \(String(format: "%.2f", Date().timeIntervalSince(createStart) * 1000))ms"
        )

        // Start the coordinator in the background - this was causing the 46-second delay due to actor isolation
        // Running it in a detached task without awaiting allows it to initialize independently
        Task.detached(priority: .userInitiated) {
            await index.coordinator.start(projectRoot: projectRoot)
            Swift.print("[DIAG] CodebaseIndex.create: coordinator started in background")
        }

        // Don't await the coordinator start - let it run in background
        // The index is usable once initializationState completes
        Swift.print(
            "[DIAG] CodebaseIndex.create END in \(String(format: "%.2f", Date().timeIntervalSince(createStart) * 1000))ms"
        )
        return index
    }

    /// Creates a placeholder index that initializes in the background
    /// The index becomes usable once initializationState.awaitInitialization() completes
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

        let tempEmbeddingGenerator = MemoryEmbeddingGeneratorFactory.makeDefault(
            projectRoot: projectRoot)

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
        let initStart = Date()
        Swift.print("[DIAG] CodebaseIndex.init START")

        self.eventBus = eventBus
        self.projectRoot = projectRoot
        self.aiService = aiService
        self.excludePatterns = config.excludePatterns
        self.isEnabled = config.configuration.enabled
        self.dbPath = Self.makeDatabasePath(
            projectRoot: projectRoot,
            storageDirectoryPath: config.configuration.storageDirectoryPath
        )

        Swift.print("[DIAG] CodebaseIndex.init storing database reference...")
        self.database = database

        Swift.print("[DIAG] CodebaseIndex.init storing embeddingGenerator reference...")
        self.memoryEmbeddingGenerator = embeddingGenerator

        Swift.print("[DIAG] CodebaseIndex.init creating IndexerActor...")
        let indexerStart = Date()
        self.indexer = IndexerActor(database: database, config: config.configuration)
        Swift.print(
            "[DIAG] CodebaseIndex.init IndexerActor created in \(String(format: "%.2f", Date().timeIntervalSince(indexerStart) * 1000))ms"
        )

        Swift.print("[DIAG] CodebaseIndex.init creating MemoryManager...")
        let memStart = Date()
        self.memoryManager = MemoryManager(
            database: database,
            eventBus: eventBus,
            embeddingGenerator: memoryEmbeddingGenerator
        )
        Swift.print(
            "[DIAG] CodebaseIndex.init MemoryManager created in \(String(format: "%.2f", Date().timeIntervalSince(memStart) * 1000))ms"
        )

        Swift.print("[DIAG] CodebaseIndex.init creating QueryService...")
        let queryStart = Date()
        self.queryService = QueryService(database: database)
        Swift.print(
            "[DIAG] CodebaseIndex.init QueryService created in \(String(format: "%.2f", Date().timeIntervalSince(queryStart) * 1000))ms"
        )

        Swift.print("[DIAG] CodebaseIndex.init creating IndexCoordinator...")
        let coordStart = Date()
        self.coordinator = IndexCoordinator(
            eventBus: eventBus,
            indexer: indexer,
            config: config.configuration,
            projectRoot: projectRoot
        )
        Swift.print(
            "[DIAG] CodebaseIndex.init IndexCoordinator created in \(String(format: "%.2f", Date().timeIntervalSince(coordStart) * 1000))ms"
        )

        Swift.print(
            "[DIAG] CodebaseIndex.init END total: \(String(format: "%.2f", Date().timeIntervalSince(initStart) * 1000))ms"
        )
    }

    public func upgradeEmbeddingGenerator(_ generator: any MemoryEmbeddingGenerating) {
        self.memoryEmbeddingGenerator = generator
        Task {
            await memoryManager.updateEmbeddingGenerator(generator)
        }
    }

    /// Returns the identifier of the current embedding model for display purposes
    public var currentEmbeddingModelIdentifier: String {
        memoryEmbeddingGenerator.modelIdentifier
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
        return ResolvedIndexConfiguration(
            configuration: resolvedConfig, excludePatterns: resolvedExcludePatterns)
    }

    private nonisolated static func makeDatabasePath(
        projectRoot: URL, storageDirectoryPath: String?
    ) -> String {
        resolveIndexDirectory(projectRoot: projectRoot, storageDirectoryPath: storageDirectoryPath)
            .appendingPathComponent("codebase.sqlite")
            .path
    }
}
