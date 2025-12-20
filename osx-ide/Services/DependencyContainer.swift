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
    
    // MARK: - Service Instances
    
    private let _errorManager: ErrorManager
    private let _uiService: UIService
    private let _workspaceService: WorkspaceService
    private let _fileEditorService: FileEditorService
    private let _aiService: AIService
    private let _conversationManager: ConversationManager
    
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
        self._errorManager = ErrorManager()
        self._uiService = UIService(errorManager: _errorManager)
        self._workspaceService = WorkspaceService(errorManager: _errorManager)
        self._fileEditorService = FileEditorService(errorManager: _errorManager)
        self._aiService = SampleAIService()
        self._conversationManager = ConversationManager(aiService: _aiService, errorManager: _errorManager)
    }
    
    // MARK: - Factory Methods
    
    /// Creates a configured AppState instance
    func makeAppState() -> AppState {
        return AppState(
            errorManager: _errorManager,
            uiService: _uiService,
            workspaceService: _workspaceService,
            fileEditorService: _fileEditorService,
            conversationManager: conversationManager
        )
    }
    
    /// Updates the AI service used by the application
    func updateAIService(_ newService: AIService) {
        _conversationManager.updateAIService(newService)
    }
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
