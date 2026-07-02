import Foundation

enum FileToolWriteApplier {
    struct ApplyWriteRequest {
        let fileSystemService: FileSystemService
        let eventBus: EventBusProtocol
        let url: URL
        let relativePath: String
        let content: String
        let traceType: String
        let conversationId: String?
    }

    struct DestructiveWriteGuardError: LocalizedError {
        let description: String

        var errorDescription: String? {
            description
        }
    }

    @MainActor
    static func applyWrite(_ request: ApplyWriteRequest) async throws {
        try await validateWriteSafety(request)

        await AIToolTraceLogger.shared.log(type: request.traceType, data: [
            "path": request.relativePath,
            "bytes": request.content.utf8.count
        ])

        let fileOperationsService = FileOperationsService(
            fileSystemService: request.fileSystemService,
            eventBus: request.eventBus
        )
        try await fileOperationsService.writeFile(content: request.content, to: request.url)
    }

    private static func validateWriteSafety(_ request: ApplyWriteRequest) async throws {
        let fileManager = FileManager.default
        let fileExists = fileManager.fileExists(atPath: request.url.path)
        let trimmedContent = request.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard fileExists else { return }

        let existingContent = try? request.fileSystemService.readFile(at: request.url)
        let existingIsEmpty = existingContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true

        if trimmedContent.isEmpty && !existingIsEmpty {
            throw DestructiveWriteGuardError(
                description: "Refused destructive overwrite of existing non-empty file \(request.relativePath) with empty content. Use patch_file for targeted edits."
            )
        }

        if let existingContent,
            !existingContent.isEmpty,
            existingContent != request.content,
            request.traceType == "fs.write_file" {
            let fileWasReadInConversation = await ToolFileAccessLedger.shared.hasRead(
                relativePath: request.relativePath,
                conversationId: request.conversationId
            )
            if fileWasReadInConversation {
                return
            }
            throw DestructiveWriteGuardError(
                description: "Refused full-file overwrite of existing file \(request.relativePath). Use patch_file for targeted edits. Read the file first with read_file, then use patch_file with line numbers from the read output."
            )
        }
    }
}
