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
    private let fileOperationsService: FileOperationsService

    init(
        errorManager: ErrorManagerProtocol,
        eventBus: EventBusProtocol,
        fileSystemService: FileSystemService
    ) {
        self.errorManager = errorManager
        self.eventBus = eventBus
        self.fileOperationsService = FileOperationsService(
            fileSystemService: fileSystemService,
            eventBus: eventBus
        )
        self.settingsStore = SettingsStore(userDefaults: .standard)
        self.currentDirectory = Self.restoreCurrentDirectoryFromUserDefaults(settingsStore: settingsStore)
    }

    private func saveCurrentDirectoryToUserDefaults(_ url: URL?) {
        guard let url else {
            settingsStore.removeObject(forKey: AppConstantsStorage.lastWorkspacePathKey)
            return
        }
        settingsStore.set(url.standardizedFileURL.path, forKey: AppConstantsStorage.lastWorkspacePathKey)
    }

    private static func restoreCurrentDirectoryFromUserDefaults(settingsStore: SettingsStore) -> URL? {
        guard let path = settingsStore.string(forKey: AppConstantsStorage.lastWorkspacePathKey), !path.isEmpty else {
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
        do {
            try fileOperationsService.deleteItem(at: url)
        } catch {
            handleError(mapToAppError(error, operation: "delete"))
        }
    }

    func renameItem(at url: URL, to newName: String) -> URL? {
        do {
            return try fileOperationsService.renameItem(at: url, to: newName)
        } catch {
            handleError(mapToAppError(error, operation: "rename"))
            return nil
        }
    }

    /// Create a new file in the specified directory
    func createFile(named name: String, in directory: URL) {
        do {
            _ = try fileOperationsService.createFile(named: name, in: directory)
        } catch {
            handleError(mapToAppError(error, operation: "create file"))
        }
    }

    /// Create a new folder in the specified directory
    func createFolder(named name: String, in directory: URL) {
        do {
            try fileOperationsService.createFolder(named: name, in: directory)
        } catch {
            handleError(mapToAppError(error, operation: "create folder"))
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
        _ = URL(fileURLWithPath: path)
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
