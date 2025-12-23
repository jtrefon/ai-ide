//
//  FileEditorService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation
import SwiftUI

/// Manages file editing operations and state
@MainActor
class FileEditorService: ObservableObject, FileEditorServiceProtocol {
    @Published var selectedFile: String? = nil
    @Published var editorContent = "" {
        didSet {
            if !isLoadingFile {
                isDirty = true
            }
        }
    }
    @Published var editorLanguage = "swift"
    @Published var isDirty = false
    
    private var isLoadingFile = false
    private let errorManager: ErrorManagerProtocol
    private let fileSystemService: FileSystemService
    private let eventBus: EventBusProtocol
    
    init(errorManager: ErrorManagerProtocol, fileSystemService: FileSystemService, eventBus: EventBusProtocol) {
        self.errorManager = errorManager
        self.fileSystemService = fileSystemService
        self.eventBus = eventBus
    }
    
    /// Handle error through the service's error manager
    func handleError(_ error: AppError) {
        errorManager.handle(error)
    }
    
    /// Load file content into editor
    func loadFile(from url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            return // Directory loading handled by WorkspaceService
        }
        
        isLoadingFile = true
        defer { isLoadingFile = false }
        
        do {
            let content = try fileSystemService.readFile(at: url)
            self.selectedFile = url.path
            self.editorContent = content
            self.editorLanguage = Self.languageForFileExtension(url.pathExtension)
            self.isDirty = false
        } catch {
            errorManager.handle(.fileOperationFailed("load file", underlying: error))
        }
    }
    
    /// Save current content to selected file
    func saveFile() {
        guard let filePath = selectedFile else { return }
        
        do {
            try fileSystemService.writeFile(content: editorContent, toPath: filePath)
            isDirty = false
            eventBus.publish(FileModifiedEvent(url: URL(fileURLWithPath: filePath)))
        } catch {
            errorManager.handle(.fileOperationFailed("save file", underlying: error))
        }
    }
    
    /// Save file to new location
    func saveFileAs(to url: URL) {
        let oldPath = selectedFile
        do {
            try fileSystemService.writeFile(content: editorContent, to: url)
            selectedFile = url.path
            editorLanguage = Self.languageForFileExtension(url.pathExtension)
            isDirty = false
            if let oldPath, oldPath != url.path {
                eventBus.publish(FileRenamedEvent(oldUrl: URL(fileURLWithPath: oldPath), newUrl: url))
            } else {
                eventBus.publish(FileCreatedEvent(url: url))
            }
            eventBus.publish(FileModifiedEvent(url: url))
        } catch {
            errorManager.handle(.fileOperationFailed("save file as", underlying: error))
        }
    }
    
    /// Create new empty file
    func newFile() {
        selectedFile = nil
        editorContent = ""
        isDirty = false
    }
    
    /// Get language identifier for file extension
    static func languageForFileExtension(_ extension: String) -> String {
        switch `extension`.lowercased() {
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
    
    /// Check if file can be saved
    var canSave: Bool {
        return isDirty && selectedFile != nil
    }
    
    /// Get current file name for display
    var displayName: String {
        return selectedFile != nil ? 
            URL(fileURLWithPath: selectedFile!).lastPathComponent : "Untitled"
    }
}
