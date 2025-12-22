//
//  AppState.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//  Refactored to be a simple coordinator between specialized state managers
//

import SwiftUI
import Combine

/// Main application state coordinator that manages interaction between specialized state managers
@MainActor
class AppState: ObservableObject {
    
    // MARK: - State Managers (Dependency Inversion)
    
    private let fileEditorStateManager: FileEditorStateManager
    private let workspaceStateManager: WorkspaceStateManager
    private let uiStateManager: UIStateManager
    
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
    
    // MARK: - Published Properties (Delegated to State Managers)
    
    // File Editor State
    var selectedFile: String? {
        return fileEditorStateManager.selectedFile
    }
    
    var editorContent: String {
        get { fileEditorStateManager.editorContent }
        set { fileEditorStateManager.updateEditorContent(newValue) }
    }
    
    var editorLanguage: String {
        get { fileEditorStateManager.editorLanguage }
        set { fileEditorStateManager.setEditorLanguage(newValue) }
    }
    
    var isDirty: Bool {
        return fileEditorStateManager.isDirty
    }
    
    var canSave: Bool {
        return fileEditorStateManager.canSave
    }
    
    var displayName: String {
        return fileEditorStateManager.displayName
    }
    
    // Workspace State
    var currentDirectory: URL? {
        return workspaceStateManager.currentDirectory
    }
    
    var openFiles: [URL] {
        return workspaceStateManager.getOpenFiles()
    }
    
    var workspaceDisplayName: String {
        return workspaceStateManager.workspaceDisplayName
    }
    
    var isWorkspaceEmpty: Bool {
        return workspaceStateManager.isWorkspaceEmpty
    }
    
    // UI State
    var isSidebarVisible: Bool {
        get { uiStateManager.isSidebarVisible }
        set { uiStateManager.setSidebarVisible(newValue) }
    }
    
    var showLineNumbers: Bool {
        get { uiStateManager.showLineNumbers }
        set { uiStateManager.setShowLineNumbers(newValue) }
    }
    
    var wordWrap: Bool {
        get { uiStateManager.wordWrap }
        set { uiStateManager.setWordWrap(newValue) }
    }
    
    var minimapVisible: Bool {
        get { uiStateManager.minimapVisible }
        set { uiStateManager.setMinimapVisible(newValue) }
    }
    
    var fontSize: Double {
        get { uiStateManager.fontSize }
        set { uiStateManager.updateFontSize(newValue) }
    }
    
    var fontFamily: String {
        get { uiStateManager.fontFamily }
        set { uiStateManager.updateFontFamily(newValue) }
    }
    
    var selectedTheme: AppTheme {
        get { uiStateManager.selectedTheme }
        set { uiStateManager.setTheme(newValue) }
    }
    
    // Conversation State
    var conversationState: ConversationManagerProtocol {
        return conversationManager
    }
    
    // Error State
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
        self.fileEditorStateManager = FileEditorStateManager(
            fileEditorService: fileEditorService,
            fileDialogService: fileDialogService
        )
        self.workspaceStateManager = WorkspaceStateManager(
            workspaceService: workspaceService,
            fileDialogService: fileDialogService
        )
        self.uiStateManager = UIStateManager(uiService: uiService)
        
        // Set up state observation
        setupStateObservation()
    }
    
    // MARK: - State Coordination Methods
    
    // File Operations
    func newFile() {
        fileEditorStateManager.newFile()
    }
    
    func loadFile(from url: URL) {
        fileEditorStateManager.loadFile(from: url)
        workspaceStateManager.addOpenFile(url)
    }
    
    func saveFile() {
        fileEditorStateManager.saveFile()
    }
    
    func saveFileAs() {
        Task { @MainActor in
            await fileEditorStateManager.saveFileAs()
        }
    }
    
    // Workspace Operations
    func openFile() {
        Task { @MainActor in
            await workspaceStateManager.openFileOrFolder { [weak self] url in
                self?.loadFile(from: url)
            }
        }
    }
    
    func openFolder() {
        Task { @MainActor in
            await workspaceStateManager.openFolder()
        }
    }
    
    func createFile(name: String) {
        workspaceStateManager.createFile(named: name)
    }
    
    func createFolder(name: String) {
        workspaceStateManager.createFolder(named: name)
    }
    
    func navigateToParent() {
        workspaceStateManager.navigateToParent()
    }
    
    // UI Operations
    func toggleSidebar() {
        uiStateManager.toggleSidebar()
    }
    
    func setSidebarVisible(_ visible: Bool) {
        uiStateManager.setSidebarVisible(visible)
    }
    
    func resetSettings() {
        uiStateManager.resetToDefaults()
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
        fileEditorStateManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Observe workspace changes
        workspaceStateManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                // Update conversation manager project root if workspace changed
                if let currentDir = self?.workspaceStateManager.currentDirectory {
                    self?.conversationManager.updateProjectRoot(currentDir)
                }
            }
            .store(in: &cancellables)
        
        // Observe UI changes
        uiStateManager.objectWillChange
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
