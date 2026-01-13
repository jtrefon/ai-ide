import Foundation

enum FileToolWriteApplier {
    static func applyWrite(
        fileSystemService: FileSystemService,
        eventBus: EventBusProtocol,
        url: URL,
        relativePath: String,
        content: String,
        traceType: String
    ) async throws {
        await AIToolTraceLogger.shared.log(type: traceType, data: [
            "path": relativePath,
            "bytes": content.utf8.count
        ])

        let existed = FileManager.default.fileExists(atPath: url.path)
        try fileSystemService.writeFile(content: content, to: url)

        Task { @MainActor in
            if existed {
                eventBus.publish(FileModifiedEvent(url: url))
            } else {
                eventBus.publish(FileCreatedEvent(url: url))
            }
        }
    }
}
