import Foundation

enum FileToolWriteApplier {
    struct ApplyWriteRequest {
        let fileSystemService: FileSystemService
        let eventBus: EventBusProtocol
        let url: URL
        let relativePath: String
        let content: String
        let traceType: String
    }

    struct DestructiveWriteGuardError: LocalizedError {
        let description: String

        var errorDescription: String? {
            description
        }
    }

    static func applyWrite(_ request: ApplyWriteRequest) async throws {
        try validateWriteSafety(request)

        await AIToolTraceLogger.shared.log(type: request.traceType, data: [
            "path": request.relativePath,
            "bytes": request.content.utf8.count
        ])

        try await MainActor.run {
            let fileOperationsService = FileOperationsService(
                fileSystemService: request.fileSystemService,
                eventBus: request.eventBus
            )
            try fileOperationsService.writeFile(content: request.content, to: request.url)
        }
    }

    private static func validateWriteSafety(_ request: ApplyWriteRequest) throws {
        let fileManager = FileManager.default
        let fileExists = fileManager.fileExists(atPath: request.url.path)
        let trimmedContent = request.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard fileExists else { return }

        let existingContent = try? request.fileSystemService.readFile(at: request.url)
        let existingIsEmpty = existingContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true

        if trimmedContent.isEmpty && !existingIsEmpty {
            throw DestructiveWriteGuardError(
                description: "Refused destructive overwrite of existing non-empty file \(request.relativePath) with empty content. Use replace_in_file for edits or create_file only for new empty files."
            )
        }

        if let existingContent,
            !existingContent.isEmpty,
            existingContent != request.content,
            request.traceType == "fs.write_file" {
            throw DestructiveWriteGuardError(
                description: "Refused full-file overwrite of existing file \(request.relativePath). Use replace_in_file for targeted edits. Reserve write_file for new files or complete intentional rewrites after reading current contents."
            )
        }
    }
}
