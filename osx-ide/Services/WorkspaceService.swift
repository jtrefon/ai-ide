import Foundation
import SwiftUI

/// Manages workspace and directory operations including file/folder creation and directory navigation
@MainActor
final class WorkspaceService: ObservableObject {
    @Published var currentDirectory: URL?
    
    private let errorManager: ErrorManager
    
    init(errorManager: ErrorManager) {
        self.errorManager = errorManager
        // Set default directory to user's home directory
        self.currentDirectory = FileManager.default.homeDirectoryForCurrentUser
    }
    
    enum WorkspaceError: Error {
        case alreadyExists(String)
        case invalidPath(String)
        case creationFailed(String, underlying: Error)
    }
    
    /// Create a new file in the specified directory
    func createFile(named name: String, in directory: URL) {
        errorManager.handleError({
            let newFileURL = directory.appendingPathComponent(name)
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: newFileURL.path) {
                throw AppError.fileOperationFailed("create file", underlying: WorkspaceError.alreadyExists(name))
            }
            
            try "".write(to: newFileURL, atomically: true, encoding: .utf8)
        }, context: "Creating file: \(name)")
    }
    
    /// Create a new folder in the specified directory
    func createFolder(named name: String, in directory: URL) {
        errorManager.handleError({
            let newFolderURL = directory.appendingPathComponent(name)
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: newFolderURL.path) {
                throw AppError.fileOperationFailed("create folder", underlying: WorkspaceError.alreadyExists(name))
            }
            
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
        }, context: "Creating folder: \(name)")
    }
    
    /// Open file dialog for selecting files or directories
    /// - Parameter onFileSelected: Callback invoked when a file (not directory) is selected
    func openFileOrFolder(onFileSelected: ((URL) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.swiftSource, .plainText, .sourceCode, .folder]
        
        if panel.runModal() == .OK, let url = panel.url {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            if isDirectory {
                self.currentDirectory = url
            } else {
                self.currentDirectory = url.deletingLastPathComponent()
                onFileSelected?(url)
            }
        }
    }
    
    /// Open folder dialog specifically for directories
    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            self.currentDirectory = url
        }
    }
    
    /// Navigate to parent directory
    func navigateToParent() {
        guard let current = currentDirectory else { return }
        
        let parent = current.deletingLastPathComponent()
        if parent.path != current.path { // Prevent going above root
            currentDirectory = parent
        }
    }
    
    /// Navigate to subdirectory
    func navigateTo(subdirectory: String) {
        guard let current = currentDirectory else { return }
        
        let newURL = current.appendingPathComponent(subdirectory)
        var isDirectory: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: newURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            currentDirectory = newURL
        } else {
            errorManager.handle(.invalidFilePath(subdirectory))
        }
    }
    
    /// Check if path is valid and accessible
    func isValidPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    }
}
