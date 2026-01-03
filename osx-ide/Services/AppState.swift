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
class AppState: ObservableObject {
    
    // MARK: - State Managers (Dependency Inversion)
    
    var fileEditor: FileEditorStateManager
    var workspace: WorkspaceStateManager
    var ui: UIStateManager
    
    @Published var fileTreeExpandedRelativePaths: Set<String> = []

     @Published var showHiddenFilesInFileTree: Bool = false
    
    // MARK: - Services
    
    private let errorManager: ErrorManagerProtocol
    let uiService: UIServiceProtocol
    let workspaceService: WorkspaceServiceProtocol
    let fileEditorService: FileEditorServiceProtocol
    let conversationManager: ConversationManagerProtocol
    let fileDialogService: FileDialogServiceProtocol
    let fileSystemService: FileSystemService
    
    private let projectSessionStore = ProjectSessionStore()
    private weak var window: NSWindow?
    private var saveSessionTask: Task<Void, Never>?
    private var isRestoringSession: Bool = false
    
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
        fileSystemService: FileSystemService
    ) {
        self.errorManager = errorManager
        self.uiService = uiService
        self.workspaceService = workspaceService
        self.fileEditorService = fileEditorService
        self.conversationManager = conversationManager
        self.fileDialogService = fileDialogService
        self.fileSystemService = fileSystemService
        
        // Initialize specialized state managers
        self.fileEditor = FileEditorStateManager(
            fileEditorService: fileEditorService,
            fileDialogService: fileDialogService
        )
        self.workspace = WorkspaceStateManager(
            workspaceService: workspaceService,
            fileDialogService: fileDialogService
        )
        self.ui = UIStateManager(uiService: uiService)
        
        // Set up state observation
        setupStateObservation()

        if let root = self.workspace.currentDirectory {
            Task { [weak self] in
                await self?.loadProjectSession(for: root)
            }
        }
    }
    
    func attachWindow(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSaveProjectSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSaveProjectSession()
            }
            .store(in: &cancellables)
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

    // MARK: - Private Methods
    private func setupStateObservation() {
        // Observe file editor changes
        fileEditor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Observe workspace changes
        workspace.$currentDirectory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDir in
                self?.objectWillChange.send()
                guard let self else { return }
                guard let newDir else { return }
                self.conversationManager.updateProjectRoot(newDir)
                DependencyContainer.shared.configureCodebaseIndex(projectRoot: newDir)

                Task { [weak self] in
                    await self?.loadProjectSession(for: newDir)
                }
            }
            .store(in: &cancellables)
        
        // Observe UI changes
        ui.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.scheduleSaveProjectSession()
            }
            .store(in: &cancellables)
        
        // Observe conversation changes
        conversationManager.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.scheduleSaveProjectSession()
            }
            .store(in: &cancellables)

        $fileTreeExpandedRelativePaths
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSaveProjectSession()
            }
            .store(in: &cancellables)

         $showHiddenFilesInFileTree
             .receive(on: DispatchQueue.main)
             .sink { [weak self] _ in
                 self?.scheduleSaveProjectSession()
             }
             .store(in: &cancellables)
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


    private func loadProjectSession(for projectRoot: URL) async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        await projectSessionStore.setProjectRoot(projectRoot)

        guard let session = try? await projectSessionStore.load() else {
            scheduleSaveProjectSession()
            return
        }

        if let frame = session.windowFrame?.rect, let window {
            window.setFrame(frame, display: true)
        }

        ui.isSidebarVisible = session.isSidebarVisible
        ui.isTerminalVisible = session.isTerminalVisible
        ui.isAIChatVisible = session.isAIChatVisible
        ui.sidebarWidth = session.sidebarWidth
        ui.terminalHeight = session.terminalHeight
        ui.chatPanelWidth = session.chatPanelWidth

         if let theme = AppTheme(rawValue: session.selectedThemeRawValue) {
             ui.selectedTheme = theme
         }
         ui.showLineNumbers = session.showLineNumbers
         ui.wordWrap = session.wordWrap
         ui.minimapVisible = session.minimapVisible

         showHiddenFilesInFileTree = session.showHiddenFilesInFileTree

        if let mode = AIMode(rawValue: session.aiModeRawValue) {
            conversationManager.currentMode = mode
        }

        fileTreeExpandedRelativePaths = Set(session.fileTreeExpandedRelativePaths)

        if let rel = session.lastOpenFileRelativePath {
            let url = projectRoot.appendingPathComponent(rel)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if FileManager.default.fileExists(atPath: url.path), !isDir {
                loadFile(from: url)
            }
        }
    }

    private func scheduleSaveProjectSession() {
        guard !isRestoringSession else { return }
        saveSessionTask?.cancel()
        saveSessionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.saveProjectSessionNow()
            }
        }
    }

    private func saveProjectSessionNow() {
        guard !isRestoringSession else { return }
        guard let projectRoot = workspace.currentDirectory else { return }

        let windowFrame = window.map { ProjectSession.WindowFrame(rect: $0.frame) }
        let lastOpenRelative: String?
        if let selectedPath = fileEditor.selectedFile {
            let selectedURL = URL(fileURLWithPath: selectedPath)
            lastOpenRelative = relativePath(for: selectedURL)
        } else {
            lastOpenRelative = nil
        }

        let session = ProjectSession(
            windowFrame: windowFrame,
            isSidebarVisible: ui.isSidebarVisible,
            isTerminalVisible: ui.isTerminalVisible,
            isAIChatVisible: ui.isAIChatVisible,
            sidebarWidth: ui.sidebarWidth,
            terminalHeight: ui.terminalHeight,
            chatPanelWidth: ui.chatPanelWidth,

             selectedThemeRawValue: ui.selectedTheme.rawValue,

             showLineNumbers: ui.showLineNumbers,
             wordWrap: ui.wordWrap,
             minimapVisible: ui.minimapVisible,

             showHiddenFilesInFileTree: showHiddenFilesInFileTree,

            aiModeRawValue: conversationManager.currentMode.rawValue,
            lastOpenFileRelativePath: lastOpenRelative,
            fileTreeExpandedRelativePaths: fileTreeExpandedRelativePaths.sorted()
        )

        Task {
            await projectSessionStore.setProjectRoot(projectRoot)
            try? await projectSessionStore.save(session)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
}
