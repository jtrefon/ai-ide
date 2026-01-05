import Foundation
import SwiftUI

/// Manages workspace and directory operations including file/folder creation and directory navigation
@MainActor
final class WorkspaceService: ObservableObject, WorkspaceServiceProtocol {
    @Published var currentDirectory: URL? {
        didSet {
            saveCurrentDirectoryToUserDefaults(currentDirectory)
        }
    }
    
    private let errorManager: ErrorManagerProtocol
    private let eventBus: EventBusProtocol
    
    init(errorManager: ErrorManagerProtocol, eventBus: EventBusProtocol) {
        self.errorManager = errorManager
        self.eventBus = eventBus
        self.currentDirectory = Self.restoreCurrentDirectoryFromUserDefaults()
    }

    private func saveCurrentDirectoryToUserDefaults(_ url: URL?) {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: AppConstants.Storage.lastWorkspacePathKey)
            return
        }
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: AppConstants.Storage.lastWorkspacePathKey)
    }

    private static func restoreCurrentDirectoryFromUserDefaults() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: AppConstants.Storage.lastWorkspacePathKey), !path.isEmpty else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL
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

     func deleteItem(at url: URL) {
         do {
             let standardized = url.standardizedFileURL
             let fileManager = FileManager.default

             if !fileManager.fileExists(atPath: standardized.path) {
                 throw AppError.fileNotFound(standardized.path)
             }

             let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

             if isDirectory {
                 let enumerator = fileManager.enumerator(
                     at: standardized,
                     includingPropertiesForKeys: nil,
                     options: [],
                     errorHandler: nil
                 )
                 while let next = enumerator?.nextObject() as? URL {
                     eventBus.publish(FileDeletedEvent(url: next.standardizedFileURL))
                 }
             }

             var resultingURL: NSURL?
             do {
                 try fileManager.trashItem(at: standardized, resultingItemURL: &resultingURL)
             } catch {
                 try fileManager.removeItem(at: standardized)
             }

             eventBus.publish(FileDeletedEvent(url: standardized))
         } catch {
             handleError(.fileOperationFailed("delete", underlying: error))
         }
     }

     func renameItem(at url: URL, to newName: String) -> URL? {
         do {
             let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
             if trimmedName.isEmpty {
                 throw AppError.invalidFilePath("New name is empty")
             }
             if trimmedName.contains("/") || trimmedName.contains("..") {
                 throw AppError.invalidFilePath("Invalid name: \(trimmedName)")
             }

             let standardized = url.standardizedFileURL
             let fileManager = FileManager.default

             if !fileManager.fileExists(atPath: standardized.path) {
                 throw AppError.fileNotFound(standardized.path)
             }

             let destination = standardized.deletingLastPathComponent().appendingPathComponent(trimmedName)
             if fileManager.fileExists(atPath: destination.path) {
                 throw AppError.fileOperationFailed("rename", underlying: WorkspaceError.alreadyExists(trimmedName))
             }

             try fileManager.moveItem(at: standardized, to: destination)
             eventBus.publish(FileRenamedEvent(oldUrl: standardized, newUrl: destination.standardizedFileURL))
             return destination.standardizedFileURL
         } catch {
             handleError(.fileOperationFailed("rename", underlying: error))
             return nil
         }
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
            eventBus.publish(FileCreatedEvent(url: newFileURL))
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
