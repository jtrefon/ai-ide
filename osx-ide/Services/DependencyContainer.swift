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

    /// Codebase index instance
    var codebaseIndex: CodebaseIndexProtocol? {
        return _codebaseIndex
    }

    var isCodebaseIndexEnabled: Bool {
        return UserDefaults.standard.object(forKey: "CodebaseIndexEnabled") as? Bool ?? true
    }

    var isAIEnrichmentIndexingEnabled: Bool {
        return UserDefaults.standard.object(forKey: "CodebaseIndexAIEnrichmentEnabled") as? Bool ?? false
    }

    func setCodebaseIndexEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "CodebaseIndexEnabled")
        _codebaseIndex?.setEnabled(enabled)
        if enabled {
            _codebaseIndex?.reindexProject(aiEnrichmentEnabled: false)
        }
    }

    func reindexProjectNow() {
        _codebaseIndex?.reindexProject(aiEnrichmentEnabled: isAIEnrichmentIndexingEnabled)
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
            _codebaseIndex?.runAIEnrichment()
        }
    }

    func configureCodebaseIndex(projectRoot: URL) {
        do {
            _codebaseIndex = try CodebaseIndex(eventBus: EventBus.shared, projectRoot: projectRoot, aiService: _aiService)
            _codebaseIndex?.start()
            _codebaseIndex?.setEnabled(isCodebaseIndexEnabled)
            if isCodebaseIndexEnabled {
                scheduleAutoReindexAfterDelay()
            }

            if let cm = _conversationManager as? ConversationManager {
                cm.updateCodebaseIndex(_codebaseIndex)
                cm.updateProjectRoot(projectRoot)
            }
        } catch {
            _codebaseIndex = nil
            print("Failed to initialize CodebaseIndex: \(error)")
        }
    }

    private func scheduleAutoReindexAfterDelay() {
        pendingAutoReindexTask?.cancel()
        pendingAutoReindexTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            guard self.isCodebaseIndexEnabled else { return }

            let aiEnabled: Bool
            if self.isAIEnrichmentIndexingEnabled {
                let settings = OpenRouterSettingsStore().load()
                let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                aiEnabled = !model.isEmpty
            } else {
                aiEnabled = false
            }

            // Resume indexing incrementally (IndexerActor skips unchanged files using last_modified).
            // If AI enrichment is enabled, CodebaseIndex will run it after baseline indexing completes.
            self._codebaseIndex?.reindexProject(aiEnrichmentEnabled: aiEnabled)
        }
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

        _codebaseIndex = nil
        _conversationManager = ConversationManager(
            aiService: _aiService,
            errorManager: errorManager,
            fileSystemService: _fileSystemService,
            codebaseIndex: nil
        )

        if let root = _workspaceService.currentDirectory {
            _conversationManager.updateProjectRoot(root)
            configureCodebaseIndex(projectRoot: root)
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
    private var _codebaseIndex: CodebaseIndexProtocol?
    private var pendingAutoReindexTask: Task<Void, Never>?
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
