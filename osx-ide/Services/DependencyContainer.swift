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

    private let settingsStore: SettingsStore

    init(isTesting: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) {
        // If testing, try to load the actual app's UserDefaults so harness has access to API keys and models
        let defaults = isTesting ? (UserDefaults(suiteName: "tdc.osx-ide") ?? .standard) : .standard
        settingsStore = SettingsStore(userDefaults: defaults)
        let errorManager = ErrorManager()
        _errorManager = errorManager
        _eventBus = EventBus()
        _commandRegistry = CommandRegistry()
        _uiRegistry = UIRegistry()
        _uiService = UIService(errorManager: errorManager, eventBus: _eventBus)
        _fileSystemService = FileSystemService()
        _workspaceService = WorkspaceService(
            errorManager: errorManager,
            eventBus: _eventBus,
            fileSystemService: _fileSystemService
        )
        _windowProvider = WindowProvider()
        _fileDialogService = FileDialogService(windowProvider: _windowProvider)
        _fileEditorService = FileEditorService(
            errorManager: errorManager,
            fileSystemService: _fileSystemService,
            eventBus: _eventBus
        )
        let openRouterService = OpenRouterAIService(
            settingsStore: OpenRouterSettingsStore(settingsStore: settingsStore),
            eventBus: _eventBus
        )
        let selectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        let localModelService = LocalModelProcessAIService(
            selectionStore: selectionStore,
            eventBus: _eventBus
        )
        _aiService = ModelRoutingAIService(
            openRouterService: openRouterService,
            localService: localModelService,
            selectionStore: selectionStore
        )

        _diagnosticsStore = DiagnosticsStore(eventBus: _eventBus)

        _conversationManager = ConversationManager(
            dependencies: ConversationManager.Dependencies(
                services: ConversationManager.ServiceDependencies(
                    aiService: _aiService,
                    errorManager: errorManager,
                    fileSystemService: _fileSystemService,
                    fileEditorService: _fileEditorService
                ),
                environment: ConversationManager.EnvironmentDependencies(
                    workspaceService: _workspaceService,
                    eventBus: _eventBus,
                    projectRoot: nil,
                    codebaseIndex: nil
                )
            )
        )

        _projectCoordinator = ProjectCoordinator(
            aiService: _aiService,
            errorManager: errorManager,
            eventBus: _eventBus,
            conversationManager: _conversationManager
        )

        if !isTesting, let root = _workspaceService.currentDirectory {
            _conversationManager.updateProjectRoot(root)
            _projectCoordinator.configureProject(root: root)
        }
    }

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

    var eventBus: EventBusProtocol {
        return _eventBus
    }

    var commandRegistry: CommandRegistry {
        return _commandRegistry
    }

    var uiRegistry: UIRegistry {
        return _uiRegistry
    }

    var diagnosticsStore: DiagnosticsStore {
        return _diagnosticsStore
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
        return settingsStore.bool(forKey: AppConstants.Storage.codebaseIndexEnabledKey, default: true)
    }

    func setCodebaseIndexEnabled(_ enabled: Bool) {
        _projectCoordinator.setIndexEnabled(enabled)
    }

    func reindexProjectNow() {
        _projectCoordinator.rebuildIndex(overwriteDB: true, aiEnrichment: isAIEnrichmentIndexingEnabled)
    }

    var isAIEnrichmentIndexingEnabled: Bool {
        return settingsStore.bool(forKey: AppConstants.Storage.codebaseIndexAIEnrichmentEnabledKey, default: false)
    }

    func setAIEnrichmentIndexingEnabled(_ enabled: Bool) {
        if enabled {
            let settings = OpenRouterSettingsStore().load(includeApiKey: false)
            let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.isEmpty {
                settingsStore.set(false, forKey: AppConstants.Storage.codebaseIndexAIEnrichmentEnabledKey)
                _errorManager.handle(.aiServiceError("OpenRouter model is not set."))
                return
            }
        }

        settingsStore.set(enabled, forKey: AppConstants.Storage.codebaseIndexAIEnrichmentEnabledKey)
        if enabled, isCodebaseIndexEnabled {
            _projectCoordinator.codebaseIndex?.runAIEnrichment()
        }
    }

    func configureCodebaseIndex(projectRoot: URL) {
        _projectCoordinator.configureProject(root: projectRoot)
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
            fileSystemService: fileSystemService,
            eventBus: eventBus,
            commandRegistry: commandRegistry,
            uiRegistry: uiRegistry,
            diagnosticsStore: diagnosticsStore,
            windowProvider: windowProvider,
            codebaseIndexProvider: { [weak self] in
                self?.codebaseIndex
            },
            configureCodebaseIndex: { [weak self] projectRoot in
                self?.configureCodebaseIndex(projectRoot: projectRoot)
            },
            setCodebaseIndexEnabled: { [weak self] enabled in
                self?.setCodebaseIndexEnabled(enabled)
            },
            setAIEnrichmentIndexingEnabled: { [weak self] enabled in
                self?.setAIEnrichmentIndexingEnabled(enabled)
            },
            reindexProjectNow: { [weak self] in
                self?.reindexProjectNow()
            }
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
    private let _eventBus: EventBus
    private let _commandRegistry: CommandRegistry
    private let _uiRegistry: UIRegistry
    private let _diagnosticsStore: DiagnosticsStore
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
        return DependencyContainer()
    }
}
#endif
