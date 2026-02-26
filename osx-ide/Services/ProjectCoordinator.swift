//
//  ProjectCoordinator.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Combine
import Foundation

/// Manages the lifecycle of a project, including indexing coordination and project-specific services.
@MainActor
class ProjectCoordinator: ObservableObject {
    private let aiService: AIService
    private let errorManager: ErrorManagerProtocol
    private let eventBus: EventBusProtocol
    private let conversationManager: ConversationManagerProtocol
    private let settingsStore: SettingsStore
    private(set) var currentProjectRoot: URL?
    private var rootWatcher: ProjectRootFileWatcher?

    @Published private(set) var codebaseIndex: CodebaseIndexProtocol?
    @Published private(set) var isInitializing: Bool = false
    @Published private(set) var initializationError: Error?

    private var pendingAutoReindexTask: Task<Void, Never>?
    private var initializationTask: Task<Void, Never>?

    init(
        aiService: AIService,
        errorManager: ErrorManagerProtocol,
        eventBus: EventBusProtocol,
        conversationManager: ConversationManagerProtocol
    ) {
        self.aiService = aiService
        self.errorManager = errorManager
        self.eventBus = eventBus
        self.conversationManager = conversationManager
        self.settingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)
    }

    /// Configure project asynchronously - does NOT block the main thread
    func configureProject(root: URL) {
        let configStart = Date()
        Swift.print("[DIAG] ProjectCoordinator.configureProject START for: \(root.path)")
        Swift.print(
            "[DIAG] Stack trace: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")

        // Check for duplicate calls
        if let current = currentProjectRoot, current == root && isInitializing {
            Swift.print(
                "[DIAG] ⚠️ DUPLICATE configureProject call detected - already initializing \(root.path)"
            )
            return
        }

        if let current = currentProjectRoot, current == root, codebaseIndex != nil {
            Swift.print(
                "[DIAG] ⚠️ DUPLICATE configureProject call detected - already configured \(root.path)"
            )
            return
        }

        currentProjectRoot = root
        pendingAutoReindexTask?.cancel()
        pendingAutoReindexTask = nil
        initializationTask?.cancel()
        initializationTask = nil

        rootWatcher?.stop()
        rootWatcher = nil

        codebaseIndex?.stop()
        codebaseIndex = nil
        initializationError = nil

        // Start async initialization
        isInitializing = true

        Swift.print("[DIAG] ProjectCoordinator.configureProject starting initializationTask")

        // Capture Sendable values for the detached task
        let eventBus = self.eventBus
        let aiService = self.aiService
        let settingsStore = self.settingsStore
        let ss = self.settingsStore

        // CRITICAL: Use Task.detached with [weak self] but WITHOUT immediate guard.
        // This keeps the closure non-isolated while allowing weak access to self for MainActor hops.
        initializationTask = Task.detached(priority: .userInitiated) { [weak self] in
            Swift.print("[DIAG] ProjectCoordinator initializationTask START (Background)")

            // Initialize logger early (non-blocking)
            await IndexLogger.shared.setup(projectRoot: root)
            await IndexLogger.shared.log(
                "ProjectCoordinator: Configuring project at \(root.path)")

            do {
                Swift.print("[DIAG] ProjectCoordinator creating CodebaseIndex...")
                let indexStart = Date()

                // Create index asynchronously - this is the heavy operation
                let index = try await CodebaseIndex.create(
                    eventBus: eventBus,
                    projectRoot: root,
                    aiService: aiService
                )

                let indexDuration = Date().timeIntervalSince(indexStart) * 1000
                Swift.print(
                    "[DIAG] ProjectCoordinator CodebaseIndex created in \(String(format: "%.2f", indexDuration))ms"
                )

                // Upgrade to CoreML embeddings in background (if available)
                // This provides semantic search instead of just keyword matching
                Task.detached(priority: .utility) {
                    let embedStart = Date()
                    let betterGenerator = await MemoryEmbeddingGeneratorFactory.makeDefaultAsync(
                        projectRoot: root
                    )
                    // Only upgrade if we got a better generator (not hashing)
                    if betterGenerator.modelIdentifier != "hashing_v1" {
                        // Call upgrade on MainActor since CodebaseIndex is MainActor-isolated
                        await MainActor.run {
                            index.upgradeEmbeddingGenerator(betterGenerator)
                        }
                        let embedDuration = Date().timeIntervalSince(embedStart) * 1000
                        Swift.print(
                            "[DIAG] Upgraded to \(betterGenerator.modelIdentifier) embeddings in \(String(format: "%.2f", embedDuration))ms"
                        )
                    } else {
                        Swift.print("[DIAG] Using hashing embeddings (CoreML not available)")
                    }
                }

                // Check if cancelled before hopping to MainActor
                if Task.isCancelled {
                    Swift.print("[DIAG] ProjectCoordinator initializationTask CANCELLED")
                    return
                }

                // Use MainActor.run specifically for final state synchronization
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.codebaseIndex = index
                    self.isInitializing = false  // CORE INIT DONE
                    index.start()

                    // Update conversation manager with new project context - safe on MainActor
                    if let cm = self.conversationManager as? ConversationManager {
                        cm.updateCodebaseIndex(index)
                        cm.updateProjectRoot(root)
                    }
                }

                // Post-init background configuration - this continues while isInitializing is false
                let isIndexEnabled = ss.bool(
                    forKey: AppConstants.Storage.codebaseIndexEnabledKey, default: true)
                await index.setEnabled(isIndexEnabled)

                if isIndexEnabled {
                    // Start reindex in background
                    await index.reindexProject(aiEnrichmentEnabled: false)
                }

                Swift.print(
                    "[DIAG] ProjectCoordinator initializationTask COMPLETE in \(String(format: "%.2f", Date().timeIntervalSince(configStart) * 1000))ms"
                )
            } catch {
                Swift.print("[DIAG] ProjectCoordinator initializationTask ERROR: \(error)")
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.codebaseIndex = nil
                    self.isInitializing = false
                    self.initializationError = error
                    self.errorManager.handle(
                        .unknown(
                            "Failed to initialize CodebaseIndex: \(error.localizedDescription)"))
                }
            }
        }
    }

    func reindexProject(aiEnrichment: Bool) {
        codebaseIndex?.reindexProject(aiEnrichmentEnabled: aiEnrichment)
    }

    func rebuildIndex(overwriteDB: Bool, aiEnrichment: Bool) {
        guard let root = currentProjectRoot else {
            Task {
                await IndexLogger.shared.log(
                    "ProjectCoordinator: Reindex requested but project root is not set")
            }
            return
        }

        pendingAutoReindexTask?.cancel()
        pendingAutoReindexTask = nil
        initializationTask?.cancel()
        initializationTask = nil

        codebaseIndex?.stop()
        codebaseIndex = nil
        isInitializing = true

        if overwriteDB {
            cleanupIndexDatabase(projectRoot: root)
        }

        initializeAndStartIndex(projectRoot: root, aiEnrichment: aiEnrichment)
    }

    private func cleanupIndexDatabase(projectRoot: URL) {
        Task {
            await IndexLogger.shared.setup(projectRoot: projectRoot)
            await IndexLogger.shared.log(
                "ProjectCoordinator: Rebuilding index DB (delete + recreate)")
        }

        let dbURL = CodebaseIndex.indexDatabaseURL(projectRoot: projectRoot)
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: dbURL.path + "-shm")

        do {
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            for url in [dbURL, walURL, shmURL] {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            errorManager.handle(.unknown("Failed to reset index DB: \(error.localizedDescription)"))
        }
    }

    private func initializeAndStartIndex(projectRoot: URL, aiEnrichment: Bool) {
        // Capture Sendable values for the detached task
        let eventBus = self.eventBus
        let aiService = self.aiService
        let settingsStore = self.settingsStore

        // CRITICAL: Use Task.detached to escape @MainActor context
        initializationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                let index = try await CodebaseIndex.create(
                    eventBus: eventBus,
                    projectRoot: projectRoot,
                    aiService: aiService
                )

                // Upgrade to CoreML embeddings in background (if available)
                Task.detached(priority: .utility) {
                    let betterGenerator = await MemoryEmbeddingGeneratorFactory.makeDefaultAsync(
                        projectRoot: projectRoot
                    )
                    // Only upgrade if we got a better generator (not hashing)
                    if betterGenerator.modelIdentifier != "hashing_v1" {
                        await MainActor.run {
                            index.upgradeEmbeddingGenerator(betterGenerator)
                        }
                        Swift.print(
                            "[DIAG] Rebuilt index: Upgraded to \(betterGenerator.modelIdentifier) embeddings"
                        )
                    }
                }

                if Task.isCancelled { return }

                // Use fire-and-forget to update main actor state without blocking
                let indexCopy = index
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.codebaseIndex = indexCopy
                    self.isInitializing = false
                    indexCopy.start()

                    if let cm = self.conversationManager as? ConversationManager {
                        cm.updateCodebaseIndex(indexCopy)
                        cm.updateProjectRoot(projectRoot)
                    }
                }

                await self.startRootWatcher(projectRoot: projectRoot)

                let isIndexEnabled = settingsStore.bool(
                    forKey: AppConstants.Storage.codebaseIndexEnabledKey, default: true)
                await index.setEnabled(isIndexEnabled)

                if isIndexEnabled {
                    await index.reindexProject(aiEnrichmentEnabled: aiEnrichment)
                } else {
                    await IndexLogger.shared.log(
                        "ProjectCoordinator: Reindex requested but Codebase Index is disabled")
                }
            } catch {
                await MainActor.run {
                    self.codebaseIndex = nil
                    self.isInitializing = false
                    self.initializationError = error
                    self.errorManager.handle(
                        .unknown("Failed to rebuild CodebaseIndex: \(error.localizedDescription)"))
                }
            }
        }
    }

    func setIndexEnabled(_ enabled: Bool) {
        settingsStore.set(enabled, forKey: AppConstants.Storage.codebaseIndexEnabledKey)
        codebaseIndex?.setEnabled(enabled)
        if enabled {
            reindexProject(aiEnrichment: false)
        }
    }

    private func scheduleAutoReindex(root: URL) {
        pendingAutoReindexTask?.cancel()
        pendingAutoReindexTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self else { return }

            let aiEnrichmentEnabled = await self.settingsStore.bool(
                forKey: AppConstants.Storage.codebaseIndexAIEnrichmentEnabledKey, default: false)
            if let index = await self.codebaseIndex {
                await index.reindexProject(aiEnrichmentEnabled: aiEnrichmentEnabled)
            }
        }
    }

    private func startRootWatcher(projectRoot: URL) {
        let excludePatterns = IndexExcludePatternManager.loadExcludePatterns(
            projectRoot: projectRoot,
            defaultPatterns: IndexConfiguration.default.excludePatterns
        )
        let watcher = ProjectRootFileWatcher(
            rootURL: projectRoot,
            eventBus: eventBus,
            excludePatterns: excludePatterns
        )
        rootWatcher = watcher
        watcher.start()
    }
}
