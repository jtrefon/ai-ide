//
//  DependencyContainer.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Combine
import SwiftUI

func elapsedSince(_ start: Date) -> Int {
    Int(Date().timeIntervalSince(start) * 1000)
}

/// Dependency injection container for managing service instances
@MainActor
class DependencyContainer: ObservableObject {
    internal let settingsStore: SettingsStore

    /// Tracks whether heavy initialization is complete
    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var initializationStatus: String = "Starting..."

    init(launchContext: AppLaunchContext = AppRuntimeEnvironment.launchContext) {
        let _initStart = Date()
        StartupLogger.log("DependencyContainer.init START")

        settingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.makeUserDefaults(for: launchContext))

        // Create lightweight services immediately
        StartupLogger.log("Creating lightweight services...")

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

        let languageModuleManager = LanguageModuleManager(
            modules: [
                SwiftModule(),
                JavaScriptModule(),
                TypeScriptModule(),
                TSXModule(),
                PythonModule(),
                HTMLModule(),
                CSSModule(),
                JSONModule()
            ],
            settingsStore: settingsStore
        )
        _languageModuleManager = languageModuleManager

        _unifiedLintingFramework = UnifiedLintingFramework(
            eventBus: _eventBus,
            diagnosticsStore: _diagnosticsStore,
            languageModuleManager: languageModuleManager,
            workspaceRootProvider: { [weak _workspaceService] in
                _workspaceService?.currentDirectory
            }
        )
        _activityCoordinator = AgentActivityCoordinator.shared
        StartupLogger.log("Lightweight services done", elapsedMs: elapsedSince(_initStart))

        // Create AI services (these are lightweight)
        StartupLogger.log("Creating AI services...")

        // Note: Test configuration will be set up asynchronously in initializeHeavyServices

        let aiServices = AIServicesFactory.makeAIServices(
            launchContext: launchContext,
            settingsStore: settingsStore,
            eventBus: _eventBus,
            activityCoordinator: _activityCoordinator
        )
        _aiService = aiServices.router
        StartupLogger.log("AI services done", elapsedMs: elapsedSince(_initStart))

        // Create conversation manager
        StartupLogger.log("Creating conversation manager...")

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
        StartupLogger.log("Conversation manager done", elapsedMs: elapsedSince(_initStart))

        // Create project coordinator
        StartupLogger.log("Creating project coordinator...")

        let projectCoordinator = ProjectCoordinator(
            aiService: _aiService,
            errorManager: errorManager,
            eventBus: _eventBus,
            conversationManager: _conversationManager
        )
        _projectCoordinator = projectCoordinator
        _inlineCompletionEngine = AIServicesFactory.makeInlineCompletionEngine(
            aiServices: aiServices,
            projectRootProvider: { [weak projectCoordinator] in projectCoordinator?.currentProjectRoot },
            codebaseIndexProvider: { [weak projectCoordinator] in projectCoordinator?.codebaseIndex }
        )
        StartupLogger.log("Project coordinator done", elapsedMs: elapsedSince(_initStart))

        StartupLogger.log("DependencyContainer.init END total", elapsedMs: elapsedSince(_initStart))

        // DO NOT set isInitialized here. Wait for heavy services background task to reach a stable "Medium" point.
        self.initializationStatus = "Starting heavy services..."

        // Defer truly heavy initialization to background - MUST use detached to escape @MainActor
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.initializeHeavyServices(launchContext: launchContext)
        }
    }

    /// Initialize heavy services asynchronously (database, embedding models, etc.)
    nonisolated private func initializeHeavyServices(launchContext: AppLaunchContext) async {
        let heavyStart = Date()
        Swift.print("[DIAG] initializeHeavyServices START (Background)")

        if launchContext.disableHeavyInit {
            await MainActor.run {
                self.isInitialized = true
                self.initializationStatus = "Ready (heavy init disabled)"
            }
            Swift.print("[DIAG] initializeHeavyServices SKIPPED due to launch context")
            return
        }

        // Small delay to let UI render first
        try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
        
        // Note: Test configuration is set up by individual tests in their setUp methods

        // Safely access currentDirectory from Main Actor
        let projectRoot = await MainActor.run { _workspaceService.currentDirectory }

        if !launchContext.isTesting, let root = projectRoot {
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

            await MainActor.run {
                _unifiedLintingFramework.runProjectScanIfNeeded()
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
    var errorManager: any ErrorManagerProtocol {
        return _errorManager
    }

    /// UI service instance
    var uiService: any UIServiceProtocol {
        return _uiService
    }

    /// Workspace service instance
    var workspaceService: any WorkspaceServiceProtocol {
        return _workspaceService
    }

    var eventBus: any EventBusProtocol {
        return _eventBus
    }

    var languageModuleManager: LanguageModuleManager {
        return _languageModuleManager
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

    var inlineCompletionEngine: InlineCompletionEngine {
        return _inlineCompletionEngine
    }

    /// File editor service instance
    var fileEditorService: any FileEditorServiceProtocol {
        return _fileEditorService
    }

    /// File system service instance
    var fileSystemService: FileSystemService {
        return _fileSystemService
    }

    /// File dialog service instance
    var fileDialogService: any FileDialogServiceProtocol {
        return _fileDialogService
    }

    var windowProvider: WindowProvider {
        return _windowProvider
    }

    /// AI service instance
    var aiService: any AIService {
        return _aiService
    }

    /// Conversation manager instance
    var conversationManager: ConversationManager {
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
        _projectCoordinator.rebuildIndex(overwriteDB: true)
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
            inlineCompletionEngine: inlineCompletionEngine,
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
            reindexProjectNow: { [weak self] in
                self?.reindexProjectNow()
            },
            refreshRemoteAIAccountBalance: { [weak self] runId in
                guard let self else { return }
                await (self._aiService as? RemoteAIAccountStatusRefreshing)?.refreshAccountBalance(runId: runId)
            }
        )
    }

    /// Updates the AI service used by the application
    func updateAIService(_ newService: any AIService) {
        _aiService = newService
        // Update the existing conversation manager's AI service instead of creating a new one
        // to preserve loaded chat history
        _conversationManager.updateAIService(newService)
    }

    // MARK: - Stored Services

    private let _errorManager: any ErrorManagerProtocol
    private let _eventBus: EventBus
    private let _commandRegistry: CommandRegistry
    private let _uiRegistry: UIRegistry
    private let _diagnosticsStore: DiagnosticsStore
    private let _uiService: any UIServiceProtocol
    private let _workspaceService: any WorkspaceServiceProtocol
    private let _fileEditorService: any FileEditorServiceProtocol
    private let _fileSystemService: FileSystemService
    private let _fileDialogService: any FileDialogServiceProtocol
    private let _windowProvider: WindowProvider
    private let _unifiedLintingFramework: UnifiedLintingFramework
    private let _languageModuleManager: LanguageModuleManager
    private var _aiService: any AIService
    private var _conversationManager: ConversationManager
    private var _projectCoordinator: ProjectCoordinator
    private let _inlineCompletionEngine: InlineCompletionEngine
    private let _activityCoordinator: any AgentActivityCoordinating
    
    /// Accessor for activity coordinator (for integration with other services)
    var activityCoordinator: any AgentActivityCoordinating {
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
