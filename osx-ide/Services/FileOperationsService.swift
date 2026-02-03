import Foundation

@MainActor
final class FileOperationsService {
    private let fileSystemService: FileSystemService
    private let eventBus: EventBusProtocol

    init(fileSystemService: FileSystemService, eventBus: EventBusProtocol) {
        self.fileSystemService = fileSystemService
        self.eventBus = eventBus
    }

    func writeFile(content: String, to url: URL) throws {
        let standardized = url.standardizedFileURL
        let existed = FileManager.default.fileExists(atPath: standardized.path)

        try fileSystemService.writeFile(content: content, to: standardized)

        if existed {
            eventBus.publish(FileModifiedEvent(url: standardized))
        } else {
            eventBus.publish(FileCreatedEvent(url: standardized))
        }
    }

    func createFile(named name: String, in directory: URL) throws -> URL {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw AppError.invalidFilePath("New name is empty")
        }
        if trimmedName.contains("/") || trimmedName.contains("..") {
            throw AppError.invalidFilePath("Invalid name: \(trimmedName)")
        }

        let newFileURL = directory.standardizedFileURL
            .appendingPathComponent(trimmedName)
            .standardizedFileURL

        if FileManager.default.fileExists(atPath: newFileURL.path) {
            throw AppError.invalidFilePath("File already exists: \(trimmedName)")
        }

        try fileSystemService.writeFile(content: "", to: newFileURL)
        eventBus.publish(FileCreatedEvent(url: newFileURL))
        return newFileURL
    }

    func createFolder(named name: String, in directory: URL) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw AppError.invalidFilePath("New name is empty")
        }
        if trimmedName.contains("/") || trimmedName.contains("..") {
            throw AppError.invalidFilePath("Invalid name: \(trimmedName)")
        }

        let newFolderURL = directory.standardizedFileURL
            .appendingPathComponent(trimmedName)
            .standardizedFileURL

        if FileManager.default.fileExists(atPath: newFolderURL.path) {
            throw AppError.invalidFilePath("Folder already exists: \(trimmedName)")
        }

        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
    }

    func deleteItem(at url: URL) throws {
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
            Task {
                await CrashReporter.shared.capture(
                    error,
                    context: CrashReportContext(operation: "FileOperationsService.deleteItem"),
                    metadata: ["path": standardized.path],
                    file: #fileID,
                    function: #function,
                    line: #line
                )
            }
            try fileManager.removeItem(at: standardized)
        }

        eventBus.publish(FileDeletedEvent(url: standardized))
    }

    func renameItem(at url: URL, to newName: String) throws -> URL {
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
            throw AppError.invalidFilePath("File already exists: \(trimmedName)")
        }

        try fileManager.moveItem(at: standardized, to: destination)
        let standardizedDestination = destination.standardizedFileURL
        eventBus.publish(FileRenamedEvent(oldUrl: standardized, newUrl: standardizedDestination))
        return standardizedDestination
    }
}
