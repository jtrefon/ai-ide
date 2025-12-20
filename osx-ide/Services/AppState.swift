//
//  AppState.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import Combine

/// Main application state coordinator that manages service interactions
@MainActor
class AppState: ObservableObject {
    // MARK: - Services
    private let _errorManager: ErrorManager
    private let _uiService: UIService
    private let _workspaceService: WorkspaceService
    private let _fileEditorService: FileEditorService
    private let _conversationManager: ConversationManager
    
    // MARK: - Service Access
    
    /// Direct access to file editor service for complex operations
    var fileEditorService: FileEditorService {
        return _fileEditorService
    }
    
    /// Direct access to workspace service for complex operations  
    var workspaceService: WorkspaceService {
        return _workspaceService
    }
    
    /// Direct access to UI service for settings
    var uiService: UIService {
        return _uiService
    }
    
    /// Direct access to error manager for error reporting
    var errorManager: ErrorManager {
        return _errorManager
    }
    
    // MARK: - Published Properties (delegated to services)
    
    // UI State
    var isSidebarVisible: Bool {
        get { _uiService.isSidebarVisible }
        set { _uiService.setSidebarVisible(newValue) }
    }
    
    // File Editor State
    var selectedFile: String? {
        get { _fileEditorService.selectedFile }
        set { 
            if let filePath = newValue {
                _fileEditorService.loadFile(from: URL(fileURLWithPath: filePath))
            }
        }
    }
    
    var editorContent: String {
        get { _fileEditorService.editorContent }
        set { _fileEditorService.editorContent = newValue }
    }
    
    var editorLanguage: String {
        get { _fileEditorService.editorLanguage }
        set { _fileEditorService.editorLanguage = newValue }
    }
    
    var isDirty: Bool {
        get { _fileEditorService.isDirty }
        set { /* Controlled by FileEditorService */ }
    }
    
    // Workspace State
    var currentDirectory: URL? {
        get { _workspaceService.currentDirectory }
        set { 
            if let newDir = newValue {
                _workspaceService.currentDirectory = newDir
            }
        }
    }
    
    // Conversation State
    var conversationManager: ConversationManager {
        get { _conversationManager }
    }
    
    // Error State
    var lastError: String? {
        get { _errorManager.currentError?.localizedDescription }
        set { 
            if newValue != nil {
                _errorManager.handle(.unknown(newValue!))
            } else {
                _errorManager.dismissError()
            }
        }
    }
    
    // MARK: - Initialization
    
    init(
        errorManager: ErrorManager,
        uiService: UIService,
        workspaceService: WorkspaceService,
        fileEditorService: FileEditorService,
        conversationManager: ConversationManager
    ) {
        self._errorManager = errorManager
        self._uiService = uiService
        self._workspaceService = workspaceService
        self._fileEditorService = fileEditorService
        self._conversationManager = conversationManager
        
        // Set up error observation
        setupErrorObservation()
    }
    
    // Convenience initializer for legacy compatibility
    convenience init() {
        let container = DependencyContainer.shared
        self.init(
            errorManager: container.errorManager,
            uiService: container.uiService,
            workspaceService: container.workspaceService,
            fileEditorService: container.fileEditorService,
            conversationManager: container.conversationManager
        )
    }
    
    // MARK: - Delegated Methods
    
    // File Operations
    func newFile() {
        _fileEditorService.newFile()
    }
    
    func loadFile(from url: URL) {
        _fileEditorService.loadFile(from: url)
    }
    
    func saveFile() {
        _fileEditorService.saveFile()
    }
    
    func saveFileAs() {
        _fileEditorService.saveFileAs()
    }
    
    // Workspace Operations
    func openFile() {
        _workspaceService.openFileOrFolder { [weak self] url in
            self?._fileEditorService.loadFile(from: url)
        }
    }
    
    func openFolder() {
        _workspaceService.openFolder()
    }
    
    func createFile(name: String) {
        if let currentDir = _workspaceService.currentDirectory {
            _workspaceService.createFile(named: name, in: currentDir)
        }
    }
    
    func createFolder(name: String) {
        if let currentDir = _workspaceService.currentDirectory {
            _workspaceService.createFolder(named: name, in: currentDir)
        }
    }
    
    // UI Operations
    func toggleSidebar() {
        _uiService.toggleSidebar()
    }
    
    func setSidebarVisible(_ visible: Bool) {
        _uiService.setSidebarVisible(visible)
    }
    
    // Conversation Operations
    func sendMessage() {
        _conversationManager.sendMessage()
    }
    
    func clearConversation() {
        _conversationManager.clearConversation()
    }
    
    // MARK: - Helper Methods
    
    /// Returns the language identifier for a given file extension
    public static func languageForFileExtension(_ fileExtension: String) -> String {
        return FileEditorService.languageForFileExtension(fileExtension)
    }
    
    // MARK: - Private Methods
    
    private func setupErrorObservation() {
        _errorManager.$currentError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        _fileEditorService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        _workspaceService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        _uiService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        _conversationManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}
