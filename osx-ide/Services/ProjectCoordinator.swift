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
class ProjectCoordinator {
    private let aiService: AIService
    private let errorManager: ErrorManagerProtocol
    private let eventBus: EventBusProtocol
    private let conversationManager: ConversationManagerProtocol
    private let settingsStore: SettingsStore
    private var currentProjectRoot: URL?

    private(set) var codebaseIndex: CodebaseIndexProtocol?
    private var pendingAutoReindexTask: Task<Void, Never>?

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

    func configureProject(root: URL) {
        currentProjectRoot = root
        pendingAutoReindexTask?.cancel()
        pendingAutoReindexTask = nil

        codebaseIndex?.stop()
        codebaseIndex = nil

        // Initialize logger early
        Task {
            await IndexLogger.shared.setup(projectRoot: root)
            await IndexLogger.shared.log("ProjectCoordinator: Configuring project at \(root.path)")
        }

        do {
            let index = try CodebaseIndex(eventBus: eventBus, projectRoot: root, aiService: aiService)
            self.codebaseIndex = index
            index.start()

            let isIndexEnabled = settingsStore.bool(forKey: AppConstantsStorage.codebaseIndexEnabledKey, default: true)
            index.setEnabled(isIndexEnabled)

            if isIndexEnabled {
                scheduleAutoReindex(root: root)
            }

            // Update conversation manager with new project context
            if let cm = conversationManager as? ConversationManager {
                cm.updateCodebaseIndex(index)
                cm.updateProjectRoot(root)
            }
        } catch {
            self.codebaseIndex = nil
            errorManager.handle(.unknown("Failed to initialize CodebaseIndex: \(error.localizedDescription)"))
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
        codebaseIndex?.stop()
        codebaseIndex = nil

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
        do {
            let index = try CodebaseIndex(eventBus: eventBus, projectRoot: projectRoot, aiService: aiService)
            self.codebaseIndex = index
            index.start()

            let isIndexEnabled = settingsStore.bool(forKey: AppConstantsStorage.codebaseIndexEnabledKey, default: true)
            index.setEnabled(isIndexEnabled)

            if let cm = conversationManager as? ConversationManager {
                cm.updateCodebaseIndex(index)
                cm.updateProjectRoot(projectRoot)
            }

            if isIndexEnabled {
                index.reindexProject(aiEnrichmentEnabled: aiEnrichment)
            } else {
                Task {
                    await IndexLogger.shared.log("ProjectCoordinator: Reindex requested but Codebase Index is disabled")
                }
            }
        } catch {
            self.codebaseIndex = nil
            errorManager.handle(.unknown("Failed to rebuild CodebaseIndex: \(error.localizedDescription)"))
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
}
