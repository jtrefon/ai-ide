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
    
    // MARK: - Services
    
    private let errorManager: ErrorManagerProtocol
    let uiService: UIServiceProtocol
    let workspaceService: WorkspaceServiceProtocol
    let fileEditorService: FileEditorServiceProtocol
    let conversationManager: ConversationManagerProtocol
    let fileDialogService: FileDialogServiceProtocol
    let fileSystemService: FileSystemService
    
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
    }
    
    // MARK: - State Coordination Methods (Keep high-level orchestration)
    
    func loadFile(from url: URL) {
        fileEditor.loadFile(from: url)
        workspace.addOpenFile(url)
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
            }
            .store(in: &cancellables)
        
        // Observe UI changes
        ui.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Observe conversation changes
        conversationManager.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Observe error changes
        errorManager.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}
