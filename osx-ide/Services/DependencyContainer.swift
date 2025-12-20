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
    var errorManager: ErrorManager {
        return _errorManager
    }
    
    /// UI service instance
    var uiService: UIService {
        return _uiService
    }
    
    /// Workspace service instance
    var workspaceService: WorkspaceService {
        return _workspaceService
    }
    
    /// File editor service instance
    var fileEditorService: FileEditorService {
        return _fileEditorService
    }
    
    /// AI service instance
    var aiService: AIService {
        return _aiService
    }
    
    /// Conversation manager instance
    var conversationManager: ConversationManager {
        return _conversationManager
    }
    
    // MARK: - Initialization
    
    private init() {
        let errorManager = ErrorManager()
        _errorManager = errorManager
        _uiService = UIService(errorManager: errorManager)
        _workspaceService = WorkspaceService(errorManager: errorManager)
        _fileEditorService = FileEditorService(errorManager: errorManager)
        _aiService = ConfigurableAIService()
        _conversationManager = ConversationManager(aiService: _aiService, errorManager: errorManager)
    }
    
    // MARK: - Factory Methods
    
    /// Creates a configured AppState instance
    func makeAppState() -> AppState {
        return AppState(
            errorManager: errorManager,
            uiService: uiService,
            workspaceService: workspaceService,
            fileEditorService: fileEditorService,
            conversationManager: conversationManager
        )
    }
    
    /// Updates the AI service used by the application
    func updateAIService(_ newService: AIService) {
        _aiService = newService
        _conversationManager = ConversationManager(aiService: newService, errorManager: _errorManager)
    }

    // MARK: - Stored Services

    private let _errorManager: ErrorManager
    private let _uiService: UIService
    private let _workspaceService: WorkspaceService
    private let _fileEditorService: FileEditorService
    private var _aiService: AIService
    private var _conversationManager: ConversationManager
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
