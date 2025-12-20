//
//  FileEditorStateManager.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Manages file editor state and operations
@MainActor
class FileEditorStateManager: ObservableObject {
    @Published var selectedFile: String? = nil
    @Published var editorContent: String = "" {
        didSet {
            if !isLoadingFile {
                isDirty = true
            }
        }
    }
    @Published var editorLanguage: String = "swift"
    @Published var isDirty: Bool = false
    
    private var isLoadingFile = false
    private let fileEditorService: FileEditorService
    private let fileDialogService: FileDialogService
    
    init(fileEditorService: FileEditorService, fileDialogService: FileDialogService) {
        self.fileEditorService = fileEditorService
        self.fileDialogService = fileDialogService
    }
    
    // MARK: - File Operations
    
    /// Load file content into editor with validation
    func loadFile(from url: URL) {
        // Input validation
        guard validateFilePath(url.path) else {
            fileEditorService.handleError(.invalidFilePath("Invalid file path: \(url.path)"))
            return
        }
        
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            return // Directory loading handled by WorkspaceStateManager
        }
        
        isLoadingFile = true
        defer { isLoadingFile = false }
        
        fileEditorService.loadFile(from: url)
        
        // Update state based on service
        selectedFile = fileEditorService.selectedFile
        editorContent = fileEditorService.editorContent
        editorLanguage = fileEditorService.editorLanguage
        isDirty = false
    }
    
    /// Save current content to selected file
    func saveFile() {
        guard selectedFile != nil else {
            saveFileAs()
            return
        }
        syncServiceState()
        fileEditorService.saveFile()
        isDirty = false
    }
    
    /// Save file to new location
    func saveFileAs() {
        syncServiceState()
        let defaultName = selectedFile != nil ?
            URL(fileURLWithPath: selectedFile!).lastPathComponent : "Untitled.swift"
        guard let url = fileDialogService.saveFile(defaultFileName: defaultName, allowedContentTypes: [.swiftSource, .plainText]) else {
            return
        }
        fileEditorService.saveFileAs(to: url)
        selectedFile = fileEditorService.selectedFile
        editorLanguage = fileEditorService.editorLanguage
        isDirty = false
    }
    
    /// Create new empty file with validation
    func newFile() {
        // Reset editor state
        fileEditorService.newFile()
        selectedFile = nil
        editorContent = ""
        isDirty = false
        editorLanguage = "swift"
    }
    
    /// Validate file path for security and correctness
    private func validateFilePath(_ path: String) -> Bool {
        // Check for empty or whitespace-only paths
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        // Check for path traversal attempts
        if path.contains("..") || path.contains("/../") {
            return false
        }
        
        // Check for invalid characters (basic validation)
        let invalidChars = CharacterSet(charactersIn: "<>:\"?*\n\r")
        guard path.rangeOfCharacter(from: invalidChars) == nil else {
            return false
        }
        
        // Check path length
        if path.count > AppConstants.FileSystem.maxPathLength {
            return false
        }
        
        return true
    }
    
    // MARK: - Content Management
    
    func updateEditorContent(_ newContent: String) {
        editorContent = newContent
        fileEditorService.editorContent = newContent
    }
    
    func setEditorLanguage(_ language: String) {
        editorLanguage = language
        fileEditorService.editorLanguage = language
    }

    private func syncServiceState() {
        fileEditorService.selectedFile = selectedFile
        fileEditorService.editorContent = editorContent
        fileEditorService.editorLanguage = editorLanguage
    }
    
    // MARK: - Computed Properties
    
    /// Check if file can be saved
    var canSave: Bool {
        return isDirty && selectedFile != nil
    }
    
    /// Get current file name for display
    var displayName: String {
        return selectedFile != nil ? 
            URL(fileURLWithPath: selectedFile!).lastPathComponent : "Untitled"
    }
    
    // MARK: - Language Detection
    
    /// Returns the language identifier for a given file extension
    static func languageForFileExtension(_ fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        default: return "text"
        }
    }
}
