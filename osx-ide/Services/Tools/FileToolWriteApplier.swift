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

    static func applyWrite(_ request: ApplyWriteRequest) async throws {
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
}
