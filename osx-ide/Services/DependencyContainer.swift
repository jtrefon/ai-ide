//
//  DependencyContainer.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI
import Combine

/// Dependency injection container for managing service instances
@MainActor
class DependencyContainer {
    
    /// Shared singleton instance
    static let shared = DependencyContainer()
    
    // MARK: - Public Accessors
    
    /// Error manager instance
    var errorManager: ErrorManagerProtocol {
        return _errorManager
    }
    
    /// UI service instance
    var uiService: UIServiceProtocol {
        return _uiService
    }
    
    /// Workspace service instance
    var workspaceService: WorkspaceServiceProtocol {
        return _workspaceService
    }
    
    /// File editor service instance
    var fileEditorService: FileEditorServiceProtocol {
        return _fileEditorService
    }

    /// File system service instance
    var fileSystemService: FileSystemService {
        return _fileSystemService
    }

    /// File dialog service instance
    var fileDialogService: FileDialogServiceProtocol {
        return _fileDialogService
    }

    var windowProvider: WindowProvider {
        return _windowProvider
    }
    
    /// AI service instance
    var aiService: AIService {
        return _aiService
    }
    
    /// Conversation manager instance
    var conversationManager: ConversationManagerProtocol {
        return _conversationManager
    }

    /// Project coordinator instance
    var projectCoordinator: ProjectCoordinator {
        return _projectCoordinator
    }
    
    /// Codebase index instance (proxied through coordinator)
    var codebaseIndex: CodebaseIndexProtocol? {
        return _projectCoordinator.codebaseIndex
    }

    var isCodebaseIndexEnabled: Bool {
        return UserDefaults.standard.object(forKey: "CodebaseIndexEnabled") as? Bool ?? true
    }

    func setCodebaseIndexEnabled(_ enabled: Bool) {
        _projectCoordinator.setIndexEnabled(enabled)
    }

    func reindexProjectNow() {
        _projectCoordinator.rebuildIndex(overwriteDB: true, aiEnrichment: isAIEnrichmentIndexingEnabled)
    }

    var isAIEnrichmentIndexingEnabled: Bool {
        return UserDefaults.standard.object(forKey: "CodebaseIndexAIEnrichmentEnabled") as? Bool ?? false
    }

    func setAIEnrichmentIndexingEnabled(_ enabled: Bool) {
        if enabled {
            let settings = OpenRouterSettingsStore().load()
            let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.isEmpty {
                UserDefaults.standard.set(false, forKey: "CodebaseIndexAIEnrichmentEnabled")
                _errorManager.handle(.aiServiceError("OpenRouter model is not set."))
                return
            }
        }

        UserDefaults.standard.set(enabled, forKey: "CodebaseIndexAIEnrichmentEnabled")
        if enabled, isCodebaseIndexEnabled {
            _projectCoordinator.codebaseIndex?.runAIEnrichment()
        }
    }

    func configureCodebaseIndex(projectRoot: URL) {
        _projectCoordinator.configureProject(root: projectRoot)
    }
    
    // MARK: - Initialization
    
    private init() {
        let errorManager = ErrorManager()
        _errorManager = errorManager
        _uiService = UIService(errorManager: errorManager)
        _workspaceService = WorkspaceService(errorManager: errorManager, eventBus: EventBus.shared)
        _fileSystemService = FileSystemService()
        _windowProvider = WindowProvider()
        _fileDialogService = FileDialogService(windowProvider: _windowProvider)
        _fileEditorService = FileEditorService(
            errorManager: errorManager,
            fileSystemService: _fileSystemService,
            eventBus: EventBus.shared
        )
        _aiService = OpenRouterAIService()

        _conversationManager = ConversationManager(
            aiService: _aiService,
            errorManager: errorManager,
            fileSystemService: _fileSystemService,
            codebaseIndex: nil
        )

        _projectCoordinator = ProjectCoordinator(
            aiService: _aiService,
            errorManager: errorManager,
            eventBus: EventBus.shared,
            conversationManager: _conversationManager
        )

        if let root = _workspaceService.currentDirectory {
            _conversationManager.updateProjectRoot(root)
            _projectCoordinator.configureProject(root: root)
        }
    }
    
    // MARK: - Factory Methods
    
    /// Creates a configured AppState instance
    func makeAppState() -> AppState {
        return AppState(
            errorManager: errorManager,
            uiService: uiService,
            workspaceService: workspaceService,
            fileEditorService: fileEditorService,
            conversationManager: conversationManager,
            fileDialogService: fileDialogService,
            fileSystemService: fileSystemService
        )
    }
    
    /// Updates the AI service used by the application
    func updateAIService(_ newService: AIService) {
        _aiService = newService
        // Update the existing conversation manager's AI service instead of creating a new one
        // to preserve loaded chat history
        if let cm = _conversationManager as? ConversationManager {
            cm.updateAIService(newService)
        }
    }

    // MARK: - Stored Services

    private let _errorManager: ErrorManagerProtocol
    private let _uiService: UIServiceProtocol
    private let _workspaceService: WorkspaceServiceProtocol
    private let _fileEditorService: FileEditorServiceProtocol
    private let _fileSystemService: FileSystemService
    private let _fileDialogService: FileDialogServiceProtocol
    private let _windowProvider: WindowProvider
    private var _aiService: AIService
    private var _conversationManager: ConversationManagerProtocol
    private var _projectCoordinator: ProjectCoordinator
}

// MARK: - Testing Support

#if DEBUG
extension DependencyContainer {
    /// Create a container with mock services for testing
    static func makeTestContainer() -> DependencyContainer {
        let container = DependencyContainer()
        // Override with mock services in tests
        return container
    }
}
#endif
