import Foundation

/// Create a new empty file
struct CreateFileTool: AITool {
    let name = "create_file"
    let description = "Create a new empty file at the specified path."
    var parameters: [String: Any] {
        FileToolParameterSchemaBuilder.objectSchema(
            properties: [
                "path": FileToolParameterSchemaBuilder.pathProperty(
                    description: "The absolute path where the file should be created."
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
                content: ""
            )
            return FileToolProposalStager.proposedCreateFileMessage(relativePath: rel, patchSetId: patchSetId)
        }

        await AIToolTraceLogger.shared.log(type: "fs.create_file", data: [
            "path": pathValidator.relativePath(for: url)
        ])
        if fileManager.fileExists(atPath: url.path) {
            throw AppError.aiServiceError(
                "create_file failed: file already exists at \(pathValidator.relativePath(for: url))"
            )
        }

        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
        try "".write(to: url, atomically: true, encoding: .utf8)
        Task { @MainActor in
            eventBus.publish(FileCreatedEvent(url: url))
        }
        return "Successfully created file at \(pathValidator.relativePath(for: url))"
    }
}
