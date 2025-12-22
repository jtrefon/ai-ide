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
    
    // MARK: - Initialization
    
    private init() {
        let errorManager = ErrorManager()
        _errorManager = errorManager
        _uiService = UIService(errorManager: errorManager)
        _workspaceService = WorkspaceService(errorManager: errorManager)
        _fileSystemService = FileSystemService()
        _windowProvider = WindowProvider()
        _fileDialogService = FileDialogService(windowProvider: _windowProvider)
        _fileEditorService = FileEditorService(
            errorManager: errorManager,
            fileSystemService: _fileSystemService
        )
        _aiService = OpenRouterAIService()
        _conversationManager = ConversationManager(
            aiService: _aiService,
            errorManager: errorManager,
            fileSystemService: _fileSystemService
        )
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
        _conversationManager = ConversationManager(
            aiService: newService,
            errorManager: _errorManager,
            fileSystemService: _fileSystemService
        )
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
