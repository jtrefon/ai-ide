//
//  ProjectCoordinator.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import Combine

/// Manages the lifecycle of a project, including indexing coordination and project-specific services.
@MainActor
class ProjectCoordinator: ObservableObject {
    private let aiService: AIService
    private let errorManager: ErrorManagerProtocol
    private let eventBus: EventBusProtocol
    private let conversationManager: ConversationManagerProtocol
    private let settingsStore: SettingsStore
    private var currentProjectRoot: URL?
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
        self.settingsStore = SettingsStore(userDefaults: .standard)
    }

    /// Configure project asynchronously - does NOT block the main thread
    func configureProject(root: URL) {
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
        
        initializationTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Initialize logger early (non-blocking)
            async let loggerSetup: Void = IndexLogger.shared.setup(projectRoot: root)
            async let loggerLog: Void = IndexLogger.shared.log("ProjectCoordinator: Configuring project at \(root.path)")
            
            // Wait for logger to be ready
            _ = await (loggerSetup, loggerLog)
            
            do {
                // Create index asynchronously - this is the heavy operation
                let index = try await CodebaseIndex.create(
                    eventBus: self.eventBus,
                    projectRoot: root,
                    aiService: self.aiService
                )
                
                // Check if cancelled
                if Task.isCancelled { return }
                
                // Update state on main actor
                await MainActor.run {
                    self.codebaseIndex = index
                    self.isInitializing = false
                    index.start()
                }
                
                // Start file watcher
                self.startRootWatcher(projectRoot: root)
                
                // Configure index settings
                let isIndexEnabled = self.settingsStore.bool(forKey: AppConstantsStorage.codebaseIndexEnabledKey, default: true)
                index.setEnabled(isIndexEnabled)
                
                if isIndexEnabled {
                    self.scheduleAutoReindex(root: root)
                }
                
                // Update conversation manager with new project context
                if let cm = self.conversationManager as? ConversationManager {
                    cm.updateCodebaseIndex(index)
                    cm.updateProjectRoot(root)
                }
            } catch {
                await MainActor.run {
                    self.codebaseIndex = nil
                    self.isInitializing = false
                    self.initializationError = error
                    self.errorManager.handle(.unknown("Failed to initialize CodebaseIndex: \(error.localizedDescription)"))
                }
            }
        }
    }

    func reindexProject(aiEnrichment: Bool) {
        codebaseIndex?.reindexProject(aiEnrichmentEnabled: aiEnrichment)
    }

    func rebuildIndex(overwriteDB: Bool, aiEnrichment: Bool) {
        guard let root = currentProjectRoot else {
            Task { await IndexLogger.shared.log("ProjectCoordinator: Reindex requested but project root is not set") }
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
            await IndexLogger.shared.log("ProjectCoordinator: Rebuilding index DB (delete + recreate)")
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
        initializationTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let index = try await CodebaseIndex.create(
                    eventBus: self.eventBus,
                    projectRoot: projectRoot,
                    aiService: self.aiService
                )
                
                if Task.isCancelled { return }
                
                await MainActor.run {
                    self.codebaseIndex = index
                    self.isInitializing = false
                    index.start()
                }
                
                self.startRootWatcher(projectRoot: projectRoot)
                
                let isIndexEnabled = self.settingsStore.bool(forKey: AppConstantsStorage.codebaseIndexEnabledKey, default: true)
                index.setEnabled(isIndexEnabled)
                
                if let cm = self.conversationManager as? ConversationManager {
                    cm.updateCodebaseIndex(index)
                    cm.updateProjectRoot(projectRoot)
                }
                
                if isIndexEnabled {
                    index.reindexProject(aiEnrichmentEnabled: aiEnrichment)
                } else {
                    await IndexLogger.shared.log("ProjectCoordinator: Reindex requested but Codebase Index is disabled")
                }
            } catch {
                await MainActor.run {
                    self.codebaseIndex = nil
                    self.isInitializing = false
                    self.initializationError = error
                    self.errorManager.handle(.unknown("Failed to rebuild CodebaseIndex: \(error.localizedDescription)"))
                }
            }
        }
    }

    func setIndexEnabled(_ enabled: Bool) {
        settingsStore.set(enabled, forKey: AppConstantsStorage.codebaseIndexEnabledKey)
        codebaseIndex?.setEnabled(enabled)
        if enabled {
            reindexProject(aiEnrichment: false)
        }
    }

    private func scheduleAutoReindex(root: URL) {
        pendingAutoReindexTask?.cancel()
        pendingAutoReindexTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self else { return }

            let aiEnrichmentEnabled = settingsStore.bool(
                forKey: AppConstantsStorage.codebaseIndexAIEnrichmentEnabledKey,
                default: false
            )
            self.reindexProject(aiEnrichment: aiEnrichmentEnabled)
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
