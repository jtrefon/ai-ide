//
//  DependencyContainer.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Combine
import SwiftUI

private func earlyDiag(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    let fm = FileManager.default
    let tmpLog = URL(fileURLWithPath: "/tmp/osx-ide-startup.log")
    if let data = line.data(using: .utf8) {
        if fm.fileExists(atPath: tmpLog.path) {
            if let handle = try? FileHandle(forWritingTo: tmpLog) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: tmpLog)
        }
    }
    Swift.print("[EARLY-DIAG] \(msg)")
    fflush(stdout)
}

/// Dependency injection container for managing service instances
@MainActor
class DependencyContainer: ObservableObject {

    internal let settingsStore: SettingsStore

    /// Tracks whether heavy initialization is complete
    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var initializationStatus: String = "Starting..."

    init(
        isTesting: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    ) {
        let _initStart = Date()
        earlyDiag("DependencyContainer.init START")

        // If testing, try to load the actual app's UserDefaults so harness has access to API keys and models
        let defaults = isTesting ? (UserDefaults(suiteName: "tdc.osx-ide") ?? .standard) : .standard
        settingsStore = SettingsStore(userDefaults: defaults)

        // Create lightweight services immediately
        earlyDiag("Creating lightweight services...")

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
        _diagnosticsStore = DiagnosticsStore(eventBus: _eventBus)
        _activityCoordinator = AgentActivityCoordinator()
        earlyDiag(
            "Lightweight services done: \(String(format: "%.0f", Date().timeIntervalSince(_initStart) * 1000))ms"
        )

        // Create AI services (these are lightweight)
        earlyDiag("Creating AI services...")
        
        // Note: Test configuration will be set up asynchronously in initializeHeavyServices

        let openRouterService = OpenRouterAIService(
            settingsStore: OpenRouterSettingsStore(settingsStore: settingsStore),
            eventBus: _eventBus,
            testConfigurationProvider: TestConfigurationProvider.shared
        )
        let selectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        let localModelService = LocalModelProcessAIService(
            selectionStore: selectionStore,
            eventBus: _eventBus,
            activityCoordinator: _activityCoordinator
        )
        _aiService = ModelRoutingAIService(
            openRouterService: openRouterService,
            localService: localModelService,
            selectionStore: selectionStore
        )
        earlyDiag(
            "AI services done: \(String(format: "%.0f", Date().timeIntervalSince(_initStart) * 1000))ms"
        )

        // Create conversation manager
        earlyDiag("Creating conversation manager...")

        _conversationManager = ConversationManager(
            dependencies: ConversationManager.Dependencies(
                services: ConversationManager.ServiceDependencies(
                    aiService: _aiService,
                    errorManager: errorManager,
                    fileSystemService: _fileSystemService,
                    fileEditorService: _fileEditorService,
                    activityCoordinator: _activityCoordinator
                ),
                environment: ConversationManager.EnvironmentDependencies(
                    workspaceService: _workspaceService,
                    eventBus: _eventBus,
                    projectRoot: nil,
                    codebaseIndex: nil
                )
            )
        )
        earlyDiag(
            "Conversation manager done: \(String(format: "%.0f", Date().timeIntervalSince(_initStart) * 1000))ms"
        )

        // Create project coordinator
        earlyDiag("Creating project coordinator...")

        _projectCoordinator = ProjectCoordinator(
            aiService: _aiService,
            errorManager: errorManager,
            eventBus: _eventBus,
            conversationManager: _conversationManager
        )
        earlyDiag(
            "Project coordinator done: \(String(format: "%.0f", Date().timeIntervalSince(_initStart) * 1000))ms"
        )

        earlyDiag(
            "DependencyContainer.init END total: \(String(format: "%.0f", Date().timeIntervalSince(_initStart) * 1000))ms"
        )

        // DO NOT set isInitialized here. Wait for heavy services background task to reach a stable "Medium" point.
        self.initializationStatus = "Starting heavy services..."

        // Defer truly heavy initialization to background - MUST use detached to escape @MainActor
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.initializeHeavyServices(isTesting: isTesting)
        }
    }

    /// Initialize heavy services asynchronously (database, embedding models, etc.)
    nonisolated private func initializeHeavyServices(isTesting: Bool) async {
        let heavyStart = Date()
        Swift.print("[DIAG] initializeHeavyServices START (Background)")

        // Small delay to let UI render first
        try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
        
        // Note: Test configuration is set up by individual tests in their setUp methods

        // Safely access currentDirectory from Main Actor
        let projectRoot = await MainActor.run { _workspaceService.currentDirectory }

        if !isTesting, let root = projectRoot {
            Swift.print("[DIAG] Setting up diagnostics logger for project: \(root.path)")

            // Setup diagnostics logger with project root
            await DiagnosticsLogger.shared.setup(projectRoot: root)
            await UIRenderDiagnostics.shared.setup(projectRoot: root)

            await DiagnosticsLogger.shared.logEvent(
                .serviceInitStart, name: "project-configure", metadata: ["projectRoot": root.path])

            // Update conversation manager with project root - safe via MainActor hop
            await MainActor.run {
                _conversationManager.updateProjectRoot(root)
            }

            // Configure project asynchronously
            let isInitialized = await MainActor.run {
                _projectCoordinator.currentProjectRoot == root
                    && _projectCoordinator.codebaseIndex != nil
            }

            if !isInitialized {
                let configStart = Date()
                Swift.print("[DIAG] Calling ProjectCoordinator.configureProject...")
                await MainActor.run {
                    self.initializationStatus = "Configuring project..."
                    _projectCoordinator.configureProject(root: root)
                }

                // Wait for the FIRST project configure to finish (CORE DONE)
                // This brings back the splash screen control
                while true {
                    let done = await MainActor.run { !_projectCoordinator.isInitializing }
                    if done { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                }

                // NO WAIT LOOP HERE. We let it initialize in background.
                // The UI will update via @Published codebaseIndex in ProjectCoordinator if needed.

                let configDuration = Date().timeIntervalSince(configStart) * 1000
                Swift.print(
                    "[DIAG] Project configure started/completed: \(String(format: "%.2f", configDuration))ms"
                )
            } else {
                Swift.print("[DIAG] Project already configured, skipping redundant initialization")
            }
        }

        await MainActor.run {
            self.isInitialized = true
            self.initializationStatus = "Ready"
        }

        let heavyDuration = Date().timeIntervalSince(heavyStart) * 1000
        Swift.print(
            "[DIAG] initializeHeavyServices END total: \(String(format: "%.2f", heavyDuration))ms")

        await DiagnosticsLogger.shared.logEvent(
            .serviceInitEnd, name: "heavy-services",
            metadata: [
                "totalDurationMs": String(format: "%.2f", heavyDuration)
            ])
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
        return settingsStore.bool(
            forKey: AppConstants.Storage.codebaseIndexEnabledKey, default: true)
    }

    func setCodebaseIndexEnabled(_ enabled: Bool) {
        _projectCoordinator.setIndexEnabled(enabled)
    }

    func reindexProjectNow() {
        _projectCoordinator.rebuildIndex(
            overwriteDB: true, aiEnrichment: isAIEnrichmentIndexingEnabled)
    }

    var isAIEnrichmentIndexingEnabled: Bool {
        return settingsStore.bool(
            forKey: AppConstants.Storage.codebaseIndexAIEnrichmentEnabledKey, default: false)
    }

    func setAIEnrichmentIndexingEnabled(_ enabled: Bool) {
        if enabled {
            let settings = OpenRouterSettingsStore().load(includeApiKey: false)
            let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.isEmpty {
                settingsStore.set(
                    false, forKey: AppConstants.Storage.codebaseIndexAIEnrichmentEnabledKey)
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
    private let _activityCoordinator: AgentActivityCoordinating
    
    /// Accessor for activity coordinator (for integration with other services)
    var activityCoordinator: AgentActivityCoordinating {
        return _activityCoordinator
    }
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
