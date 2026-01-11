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
    private let settingsStore: SettingsStore
    
    init(errorManager: ErrorManagerProtocol, eventBus: EventBusProtocol) {
        self.errorManager = errorManager
        self.eventBus = eventBus
        self.settingsStore = SettingsStore(userDefaults: .standard)
        self.currentDirectory = Self.restoreCurrentDirectoryFromUserDefaults(settingsStore: settingsStore)
    }

    private func saveCurrentDirectoryToUserDefaults(_ url: URL?) {
        guard let url else {
            settingsStore.removeObject(forKey: AppConstants.Storage.lastWorkspacePathKey)
            return
        }
        settingsStore.set(url.standardizedFileURL.path, forKey: AppConstants.Storage.lastWorkspacePathKey)
    }

    private static func restoreCurrentDirectoryFromUserDefaults(settingsStore: SettingsStore) -> URL? {
        guard let path = settingsStore.string(forKey: AppConstants.Storage.lastWorkspacePathKey), !path.isEmpty else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func mapToAppError(_ error: Error, operation: String) -> AppError {
        if let appError = error as? AppError { return appError }
        return AppError.fileOperationFailed(operation, underlying: error)
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
        switch deleteItemResult(at: url) {
        case .success:
            break
        case .failure(let error):
            handleError(error)
        }
    }

    func renameItem(at url: URL, to newName: String) -> URL? {
        switch renameItemResult(at: url, to: newName) {
        case .success(let newUrl):
            return newUrl
        case .failure(let error):
            handleError(error)
            return nil
        }
    }
    
    /// Create a new file in the specified directory
    func createFile(named name: String, in directory: URL) {
        switch createFileResult(named: name, in: directory) {
        case .success(let newFileURL):
            eventBus.publish(FileCreatedEvent(url: newFileURL))
        case .failure(let error):
            handleError(error)
        }
    }
    
    /// Create a new folder in the specified directory
    func createFolder(named name: String, in directory: URL) {
        switch createFolderResult(named: name, in: directory) {
        case .success:
            break
        case .failure(let error):
            handleError(error)
        }
    }

    private func deleteItemResult(at url: URL) -> Result<Void, AppError> {
        Result {
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
        }
        .mapError { error in
            mapToAppError(error, operation: "delete")
        }
    }

    private func renameItemResult(at url: URL, to newName: String) -> Result<URL, AppError> {
        Result {
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
                throw WorkspaceError.alreadyExists(trimmedName)
            }

            try fileManager.moveItem(at: standardized, to: destination)
            let standardizedDestination = destination.standardizedFileURL
            eventBus.publish(FileRenamedEvent(oldUrl: standardized, newUrl: standardizedDestination))
            return standardizedDestination
        }
        .mapError { error in
            mapToAppError(error, operation: "rename")
        }
    }

    private func createFileResult(named name: String, in directory: URL) -> Result<URL, AppError> {
        Result {
            let newFileURL = directory.appendingPathComponent(name).standardizedFileURL
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: newFileURL.path) {
                throw WorkspaceError.alreadyExists(name)
            }

            try "".write(to: newFileURL, atomically: true, encoding: .utf8)
            return newFileURL
        }
        .mapError { error in
            mapToAppError(error, operation: "create file")
        }
    }

    private func createFolderResult(named name: String, in directory: URL) -> Result<Void, AppError> {
        Result {
            let newFolderURL = directory.appendingPathComponent(name).standardizedFileURL
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: newFolderURL.path) {
                throw WorkspaceError.alreadyExists(name)
            }

            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
        }
        .mapError { error in
            mapToAppError(error, operation: "create folder")
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

    func makePathValidator(projectRoot: URL) -> PathValidator {
        PathValidator(projectRoot: projectRoot.standardizedFileURL)
    }

    func makePathValidatorForCurrentDirectory() -> PathValidator? {
        guard let root = currentDirectory?.standardizedFileURL else { return nil }
        return makePathValidator(projectRoot: root)
    }
}
