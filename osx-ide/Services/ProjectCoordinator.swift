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
    }
    
    func configureProject(root: URL) {
        // Initialize logger early
        Task {
            await IndexLogger.shared.setup(projectRoot: root)
            await IndexLogger.shared.log("ProjectCoordinator: Configuring project at \(root.path)")
        }
        
        do {
            let index = try CodebaseIndex(eventBus: eventBus, projectRoot: root, aiService: aiService)
            self.codebaseIndex = index
            index.start()
            
            let isIndexEnabled = UserDefaults.standard.object(forKey: "CodebaseIndexEnabled") as? Bool ?? true
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
    
    func setIndexEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "CodebaseIndexEnabled")
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
            
            let aiEnrichmentEnabled = UserDefaults.standard.object(forKey: "CodebaseIndexAIEnrichmentEnabled") as? Bool ?? false
            self.reindexProject(aiEnrichment: aiEnrichmentEnabled)
        }
    }
}
