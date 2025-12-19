//
//  AppState.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var conversationManager: ConversationManager
    @Published var isSidebarVisible = true
    @Published var selectedFile: String? = nil
    
    /// The content currently shown in the editor.
    /// Setting this marks the document as dirty, unless loading a file.
    @Published var editorContent = "" {
        didSet {
            if !isLoadingFile {
                isDirty = true
            }
        }
    }
    @Published var editorLanguage = "swift"
    
    /// The directory currently being browsed (used for open dialogs etc).
    @Published var currentDirectory: URL?
    
    /// Whether there are unsaved changes in the editor content.
    @Published var isDirty = false
    
    /// Last error message encountered during file operations, if any.
    @Published var lastError: String? = nil
    
    /// Internal flag to suppress isDirty when loading a file
    private var isLoadingFile = false
    
    init() {
        self.conversationManager = ConversationManager()
        // Set default directory to user's home directory
        self.currentDirectory = FileManager.default.homeDirectoryForCurrentUser
    }
    
    // MARK: - Editor Operations
    
    /// Presents an open file dialog. If a file is selected, loads its content and updates editor state.
    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.swiftSource, .plainText, .sourceCode]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    // Set the current directory
                    self.currentDirectory = url
                } else {
                    self.loadFile(from: url)
                }
            }
        }
    }
    
    /// Presents an open folder dialog. Updates the file explorer with the selected directory.
    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.currentDirectory = url
            }
        }
    }
    
    /// Saves the current editor content to the selected file. If no file is selected, triggers save as dialog.
    func saveFile() {
        if let filePath = selectedFile {
            // Save to existing file
            do {
                try editorContent.write(toFile: filePath, atomically: true, encoding: .utf8)
                isDirty = false
                lastError = nil
            } catch {
                let errorDescription = "Error saving file: \(error)"
                print(errorDescription)
                lastError = errorDescription
            }
        } else {
            // Save as new file
            saveFileAs()
        }
    }
    
    /// Presents a save panel and saves the current editor content to the selected location.
    func saveFileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.swiftSource, .plainText]
        panel.nameFieldStringValue = "Untitled.swift"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                do {
                    try editorContent.write(to: url, atomically: true, encoding: .utf8)
                    self.selectedFile = url.path
                    self.editorLanguage = AppState.languageForFileExtension(url.pathExtension)
                    isDirty = false
                    lastError = nil
                } catch {
                    let errorDescription = "Error saving file: \(error)"
                    print(errorDescription)
                    lastError = errorDescription
                }
            }
        }
    }
    
    /// Resets the editor content to a new empty file.
    func newFile() {
        self.selectedFile = nil
        self.editorContent = ""
        isDirty = false
    }
    
    /// Loads the file at the given URL into the editor without marking it dirty.
    public func loadFile(from url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            self.currentDirectory = url
            return
        }
        isLoadingFile = true
        defer { isLoadingFile = false }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            self.selectedFile = url.path
            self.editorContent = content
            self.editorLanguage = AppState.languageForFileExtension(url.pathExtension)
            self.isDirty = false
            self.lastError = nil
        } catch {
            let errorDescription = "Error reading file: \(error)"
            print(errorDescription)
            self.lastError = errorDescription
        }
    }
    
    // MARK: - UI State
    
    /// Toggles the visibility of the sidebar.
    func toggleSidebar() {
        isSidebarVisible.toggle()
    }
    
    // MARK: - Helper Methods
    
    /// Returns the language identifier for a given file extension.
    /// - Parameter extension: The file extension string.
    /// - Returns: A string representing the language mode.
    public static func languageForFileExtension(_ extension: String) -> String {
        switch `extension`.lowercased() {
        case "swift":
            return "swift"
        case "js", "jsx":
            return "javascript"
        case "ts", "tsx":
            return "typescript"
        case "py":
            return "python"
        case "html":
            return "html"
        case "css":
            return "css"
        case "json":
            return "json"
        default:
            return "text"
        }
    }
}
