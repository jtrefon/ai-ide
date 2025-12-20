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
    
    // MARK: - Service Factories
    
    private var serviceFactories: [String: () -> Any]
    
    // MARK: - Public Accessors
    
    /// Error manager instance
    var errorManager: ErrorManager {
        return getService("errorManager")
    }
    
    /// UI service instance
    var uiService: UIService {
        return getService("uiService")
    }
    
    /// Workspace service instance
    var workspaceService: WorkspaceService {
        return getService("workspaceService")
    }
    
    /// File editor service instance
    var fileEditorService: FileEditorService {
        return getService("fileEditorService")
    }
    
    /// AI service instance
    var aiService: AIService {
        return getService("aiService")
    }
    
    /// Conversation manager instance
    var conversationManager: ConversationManager {
        return getService("conversationManager")
    }
    
    // MARK: - Initialization
    
    private init() {
        var factories: [String: () -> Any] = [:]
        
        // Register services with proper factory functions
        factories["errorManager"] = { ErrorManager() }
        factories["uiService"] = { 
            UIService(errorManager: factories["errorManager"]!() as! ErrorManager)
        }
        factories["workspaceService"] = { 
            WorkspaceService(errorManager: factories["errorManager"]!() as! ErrorManager)
        }
        factories["fileEditorService"] = { 
            FileEditorService(errorManager: factories["errorManager"]!() as! ErrorManager)
        }
        factories["aiService"] = { ConfigurableAIService() }
        factories["conversationManager"] = { 
            ConversationManager(
                aiService: factories["aiService"]!() as! AIService,
                errorManager: factories["errorManager"]!() as! ErrorManager
            )
        }
        
        self.serviceFactories = factories
    }
    
    private func getService<T>(_ key: String) -> T {
        guard let factory = serviceFactories[key],
              let service = factory() as? T else {
            fatalError("Service not found or incorrect type: \(key)")
        }
        return service
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
        serviceFactories["aiService"] = { newService }
        serviceFactories["conversationManager"] = { [self] in
            ConversationManager(aiService: newService, errorManager: errorManager)
        }
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
