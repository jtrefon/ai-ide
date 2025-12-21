import Foundation
import SwiftUI

/// Manages workspace and directory operations including file/folder creation and directory navigation
@MainActor
final class WorkspaceService: ObservableObject, WorkspaceServiceProtocol {
    @Published var currentDirectory: URL?
    
    private let errorManager: ErrorManagerProtocol
    
    init(errorManager: ErrorManagerProtocol) {
        self.errorManager = errorManager
        // Set default directory to user's home directory
        self.currentDirectory = FileManager.default.homeDirectoryForCurrentUser
    }
    
    /// Handle error through the service's error manager
    func handleError(_ error: AppError) {
        errorManager.handle(error)
    }
    
    enum WorkspaceError: Error {
        case alreadyExists(String)
        case invalidPath(String)
        case creationFailed(String, underlying: Error)
    }
    
    /// Create a new file in the specified directory
    func createFile(named name: String, in directory: URL) {
        do {
            let newFileURL = directory.appendingPathComponent(name)
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: newFileURL.path) {
                throw AppError.fileOperationFailed("create file", underlying: WorkspaceError.alreadyExists(name))
            }
            
            try "".write(to: newFileURL, atomically: true, encoding: .utf8)
        } catch {
            handleError(.fileOperationFailed("create file", underlying: error))
        }
    }
    
    /// Create a new folder in the specified directory
    func createFolder(named name: String, in directory: URL) {
        do {
            let newFolderURL = directory.appendingPathComponent(name)
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: newFolderURL.path) {
                throw AppError.fileOperationFailed("create folder", underlying: WorkspaceError.alreadyExists(name))
            }
            
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
        } catch {
            handleError(.fileOperationFailed("create folder", underlying: error))
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
            handleError(.invalidFilePath("Directory not found: \(subdirectory)"))
        }
    }
    
    /// Check if path is valid and accessible
    func isValidPath(_ path: String) -> Bool {
        let _ = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    }
}
