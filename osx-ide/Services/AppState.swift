//
//  AppState.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//  Refactored to be a simple coordinator between specialized state managers
//

import SwiftUI
import Combine
import AppKit

/// Main application state coordinator that manages interaction between specialized state managers
@MainActor
class AppState: ObservableObject, IDEContext {

    // MARK: - State Managers (Dependency Inversion)

    var fileEditor: FileEditorStateManager
    var workspace: WorkspaceStateManager
    var ui: UIStateManager

    @Published var fileTreeExpandedRelativePaths: Set<String> = []

    @Published var fileTreeSelectedRelativePath: String?

    @Published var fileTreeRefreshToken: Int = 0

    @Published var isGlobalSearchPresented: Bool = false
    @Published var isQuickOpenPresented: Bool = false

    @Published var isCommandPalettePresented: Bool = false
    @Published var isGoToSymbolPresented: Bool = false

    @Published var isNavigationLocationsPresented: Bool = false
    @Published var navigationLocationsTitle: String = ""
    @Published var navigationLocations: [WorkspaceCodeLocation] = []

    @Published var isRenameSymbolPresented: Bool = false
    @Published var renameSymbolIdentifier: String = ""

    @Published var showHiddenFilesInFileTree: Bool = false

    @Published var languageOverridesByRelativePath: [String: String] = [:]
    @Published var isUIReady: Bool = false
    @Published var uiCompositionIssues: [String] = []

    // MARK: - Services

    private let errorManager: ErrorManagerProtocol
    let uiService: UIServiceProtocol
    let workspaceService: WorkspaceServiceProtocol
    let fileEditorService: FileEditorServiceProtocol
    let conversationManager: ConversationManagerProtocol
    let fileDialogService: FileDialogServiceProtocol
    let fileSystemService: FileSystemService

    let eventBus: EventBusProtocol
    let commandRegistry: CommandRegistry
    let uiRegistry: UIRegistry
    let diagnosticsStore: DiagnosticsStore

    let windowProvider: WindowProvider
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let configureCodebaseIndex: (URL) -> Void
    private let setCodebaseIndexEnabledImpl: (Bool) -> Void
    private let setAIEnrichmentIndexingEnabledImpl: (Bool) -> Void
    private let reindexProjectNowImpl: () -> Void
    private var eventCancellables = Set<AnyCancellable>()

    private lazy var projectSessionCoordinator = ProjectSessionCoordinator(
        workspace: workspace,
        ui: ui,
        fileEditor: fileEditor,
        conversationManager: conversationManager,
        getFileTreeExpandedRelativePaths: { [weak self] in
            self?.fileTreeExpandedRelativePaths ?? []
        },
        setFileTreeExpandedRelativePaths: { [weak self] value in
            self?.fileTreeExpandedRelativePaths = value
        },
        getShowHiddenFilesInFileTree: { [weak self] in
            self?.showHiddenFilesInFileTree ?? false
        },
        setShowHiddenFilesInFileTree: { [weak self] value in
            self?.showHiddenFilesInFileTree = value
        },
        getLanguageOverridesByRelativePath: { [weak self] in
            self?.languageOverridesByRelativePath ?? [:]
        },
        setLanguageOverridesByRelativePath: { [weak self] value in
            self?.languageOverridesByRelativePath = value
            self?.applyLanguageOverrideToActiveEditorIfPossible()
        },
        relativePathForURL: { [weak self] url in
            self?.relativePath(for: url)
        },
        loadFileFromURL: { [weak self] url in
            self?.loadFile(from: url)
        }
    )

    private lazy var workspaceLifecycleCoordinator = WorkspaceLifecycleCoordinator(
        conversationManager: conversationManager,
        configureCodebaseIndex: { projectRoot in
            self.configureCodebaseIndex(projectRoot)
        },
        loadProjectSession: { [weak self] projectRoot in
            await self?.projectSessionCoordinator.loadProjectSession(for: projectRoot)
        }
    )

    private lazy var stateObservationCoordinator = StateObservationCoordinator(
        fileEditor: fileEditor,
        workspace: workspace,
        ui: ui,
        conversationManager: conversationManager,
        onWorkspaceRootChange: { [weak self] newRoot in
            self?.workspaceLifecycleCoordinator.workspaceRootDidChange(to: newRoot)
        },
        onPersistenceRelevantChange: { [weak self] in
            self?.scheduleSaveProjectSession()
        }
    )

    // MARK: - Shared Contexts

    let selectionContext = CodeSelectionContext()

    // MARK: - Computed Properties (Convenience)

    var lastError: String? {
        get { errorManager.currentError?.localizedDescription }
        set {
            if let error = newValue {
                errorManager.handle(.unknown(error))
            } else {
                errorManager.dismissError()
            }
        }
    }

    // MARK: - Initialization

    init(
        errorManager: ErrorManagerProtocol,
        uiService: UIServiceProtocol,
        workspaceService: WorkspaceServiceProtocol,
        fileEditorService: FileEditorServiceProtocol,
        conversationManager: ConversationManagerProtocol,
        fileDialogService: FileDialogServiceProtocol,
        fileSystemService: FileSystemService,
        eventBus: EventBusProtocol,
        commandRegistry: CommandRegistry,
        uiRegistry: UIRegistry,
        diagnosticsStore: DiagnosticsStore,
        windowProvider: WindowProvider,
        codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?,
        configureCodebaseIndex: @escaping (URL) -> Void,
        setCodebaseIndexEnabled: @escaping (Bool) -> Void,
        setAIEnrichmentIndexingEnabled: @escaping (Bool) -> Void,
        reindexProjectNow: @escaping () -> Void
    ) {
        self.errorManager = errorManager
        self.uiService = uiService
        self.workspaceService = workspaceService
        self.fileEditorService = fileEditorService
        self.conversationManager = conversationManager
        self.fileDialogService = fileDialogService
        self.fileSystemService = fileSystemService

        self.eventBus = eventBus
        self.commandRegistry = commandRegistry
        self.uiRegistry = uiRegistry
        self.diagnosticsStore = diagnosticsStore

        self.windowProvider = windowProvider
        self.codebaseIndexProvider = codebaseIndexProvider
        self.configureCodebaseIndex = configureCodebaseIndex
        self.setCodebaseIndexEnabledImpl = setCodebaseIndexEnabled
        self.setAIEnrichmentIndexingEnabledImpl = setAIEnrichmentIndexingEnabled
        self.reindexProjectNowImpl = reindexProjectNow

        // Initialize specialized state managers
        self.fileEditor = FileEditorStateManager(
            fileEditorService: fileEditorService,
            fileDialogService: fileDialogService,
            fileSystemService: fileSystemService
        )
        self.workspace = WorkspaceStateManager(
            workspaceService: workspaceService,
            fileDialogService: fileDialogService
        )
        self.ui = UIStateManager(uiService: uiService, eventBus: eventBus)

        stateObservationCoordinator.startObserving(
            fileTreeExpandedRelativePathsPublisher: $fileTreeExpandedRelativePaths,
            showHiddenFilesInFileTreePublisher: $showHiddenFilesInFileTree
        )

        setupFileTreeRefreshSubscription()

        projectSessionCoordinator.loadProjectSessionIfAvailable()
    }

    func attachWindow(_ window: NSWindow) {
        projectSessionCoordinator.attachWindow(window)
    }

    func persistSessionNow() {
        projectSessionCoordinator.persistProjectSessionNow()
    }

    func setLanguageOverride(forAbsoluteFilePath filePath: String, languageIdentifier: String?) {
        guard let relative = relativePath(for: URL(fileURLWithPath: filePath)) else { return }

        if let languageIdentifier, !languageIdentifier.isEmpty {
            languageOverridesByRelativePath[relative] = languageIdentifier
        } else {
            languageOverridesByRelativePath.removeValue(forKey: relative)
        }

        applyLanguageOverrideToActiveEditorIfPossible()
        scheduleSaveProjectSession()
    }

    func effectiveLanguageIdentifier(forAbsoluteFilePath filePath: String) -> String {
        if let relative = relativePath(for: URL(fileURLWithPath: filePath)),
           let override = languageOverridesByRelativePath[relative],
           !override.isEmpty {
            return override
        }

        return FileEditorStateManager.languageForFileExtension(URL(fileURLWithPath: filePath).pathExtension)
    }

    private func applyLanguageOverrideToActiveEditorIfPossible() {
        guard let filePath = fileEditor.selectedFile else { return }
        let effective = effectiveLanguageIdentifier(forAbsoluteFilePath: filePath)
        if fileEditor.editorLanguage != effective {
            fileEditor.editorLanguage = effective
        }
    }

    var codebaseIndex: CodebaseIndexProtocol? {
        codebaseIndexProvider()
    }

    func setCodebaseIndexEnabled(_ enabled: Bool) {
        setCodebaseIndexEnabledImpl(enabled)
    }

    func setAIEnrichmentIndexingEnabled(_ enabled: Bool) {
        setAIEnrichmentIndexingEnabledImpl(enabled)
    }

    func reindexProjectNow() {
        reindexProjectNowImpl()
    }

    // MARK: - State Coordination Methods (Keep high-level orchestration)

    func loadFile(from url: URL) {
        fileEditor.loadFile(from: url)
        workspace.addOpenFile(url)
        scheduleSaveProjectSession()
    }

    func openFile() {
        Task { @MainActor in
            await workspace.openFileOrFolder { [weak self] url in
                self?.loadFile(from: url)
            }
        }
    }

    // MARK: - Convenience computed properties

    var showLineNumbers: Bool { ui.showLineNumbers }
    var wordWrap: Bool { ui.wordWrap }
    var fontSize: Double { ui.fontSize }
    var fontFamily: String { ui.fontFamily }
    var selectedTheme: AppTheme { ui.selectedTheme }

    // MARK: - Workspace Operations

    func openFolder() {
        Task { @MainActor in
            await workspace.openFolder()
        }
    }

    func createFile(name: String) {
        workspace.createFile(named: name)
    }

    func createFolder(name: String) {
        workspace.createFolder(named: name)
    }

    func navigateToParent() {
        workspace.navigateToParent()
    }

    func newProject() {
        Task { @MainActor in
            guard let projectURL = await fileDialogService.promptForNewProjectFolder(defaultName: "NewProject") else {
                return
            }
            workspace.createProject(at: projectURL)
        }
    }

    func requestFileTreeRefresh() {
        fileTreeRefreshToken += 1
    }

    // UI Operations
    func toggleSidebar() {
        ui.toggleSidebar()
    }

    func setSidebarVisible(_ visible: Bool) {
        ui.setSidebarVisible(visible)
    }

    func resetSettings() {
        ui.resetToDefaults()
    }

    // Conversation Operations
    func sendMessage() {
        conversationManager.sendMessage()
    }

    func clearConversation() {
        conversationManager.clearConversation()
    }

    // Helper Methods
    static func languageForFileExtension(_ fileExtension: String) -> String {
        return FileEditorStateManager.languageForFileExtension(fileExtension)
    }

    /// Standardized method to resolve relative path from project root.
    func relativePath(for url: URL) -> String? {
        guard let projectRoot = workspace.currentDirectory?.standardizedFileURL else { return nil }
        let standardizedURL = url.standardizedFileURL

        if standardizedURL.path.hasPrefix(projectRoot.path) {
            var relative = String(standardizedURL.path.dropFirst(projectRoot.path.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            return relative.isEmpty ? "." : relative
        }
        return nil
    }

    /// Standardized method to resolve absolute URL from relative path.
    func absoluteURL(for relativePath: String) -> URL? {
        return workspace.currentDirectory?.appendingPathComponent(relativePath)
    }

    func selectedFileTreeURL() -> URL? {
        guard let projectRoot = workspace.currentDirectory?.standardizedFileURL else { return nil }
        guard let relative = fileTreeSelectedRelativePath, !relative.isEmpty else { return nil }
        return projectRoot.appendingPathComponent(relative).standardizedFileURL
    }

    private func setupFileTreeRefreshSubscription() {
        eventBus.subscribe(to: FileTreeRefreshRequestedEvent.self) { [weak self] event in
            self?.fileEditor.handleExternalFileChanges(paths: event.paths)
            self?.requestFileTreeRefresh()
        }
        .store(in: &eventCancellables)
    }

    private func scheduleSaveProjectSession() {
        projectSessionCoordinator.scheduleSaveProjectSession()
    }
}
