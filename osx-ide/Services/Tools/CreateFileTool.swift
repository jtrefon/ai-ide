import Foundation

/// Create a new empty file
struct CreateFileTool: AITool {
    let name = "create_file"
    let description = "Reserve a new file path and ensure parent directories exist. Prefer write_file when creating a file with content."
    var parameters: [String: Any] {
        FileToolParameterSchemaBuilder.objectSchema(
            properties: [
                "path": FileToolParameterSchemaBuilder.pathProperty(
                    description: "The absolute path where the file should be created."
                ),
                "content": FileToolParameterSchemaBuilder.pathProperty(
                    description: "Optional file contents. If provided, the tool will create the file and write this content immediately."
                ),
                "mode": FileToolParameterSchemaBuilder.modeProperty(),
                "patch_set_id": FileToolParameterSchemaBuilder.patchSetIdProperty()
            ],
            required: ["path"]
        )
    }
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for create_file")
        }
        let content = arguments["content"] as? String

        let context = ToolInvocationContext.from(arguments: arguments)
        let mode = context.mode
        let toolCallId = context.toolCallId
        let patchSetId = context.patchSetId

        let url = try pathValidator.validateAndResolve(path)
        let fileManager = FileManager.default

        if mode == "propose" {
            let rel = pathValidator.relativePath(for: url)
            try await FileToolProposalStager.stageWrite(
                patchSetId: patchSetId,
                toolCallId: toolCallId,
                relativePath: rel,
                content: content ?? ""
            )
            return FileToolProposalStager.proposedCreateFileMessage(relativePath: rel, patchSetId: patchSetId)
        }

        let relativePath = pathValidator.relativePath(for: url)
        await AIToolTraceLogger.shared.log(type: "fs.create_file", data: [
            "path": relativePath
        ])

        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: url.path) {
            if let content {
                let existingContent = try String(contentsOf: url, encoding: .utf8)
                if existingContent == content {
                    return "File already exists at \(relativePath) and already matches the provided content."
                }

                try content.write(to: url, atomically: true, encoding: .utf8)
                Task { @MainActor in
                    eventBus.publish(FileModifiedEvent(url: url))
                }
                return "File already exists at \(relativePath). Updated content successfully."
            }

            return "File already exists at \(relativePath). Use write_file to update content."
        }

        if let content {
            try content.write(to: url, atomically: true, encoding: .utf8)
            Task { @MainActor in
                eventBus.publish(FileModifiedEvent(url: url))
            }
            return "Created file at \(relativePath) and wrote provided content."
        }

        await AIToolTraceLogger.shared.log(type: "fs.create_file_reserved", data: [
            "path": relativePath
        ])
        return "Reserved file path at \(relativePath). Use write_file to add content."
    }
}
