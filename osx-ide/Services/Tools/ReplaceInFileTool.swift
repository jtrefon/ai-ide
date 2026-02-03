import Foundation

/// Replace specific content in a file (diff-style editing)
struct ReplaceInFileTool: AITool {
    let name = "replace_in_file"
    let description = "Replace specific content in a file. Use this instead of write_file for large files " +
        "to avoid rewriting everything. Specify the exact text to find and what to replace it with."
    var parameters: [String: Any] {
        FileToolParameterSchemaBuilder.objectSchema(
            properties: [
                "path": FileToolParameterSchemaBuilder.pathProperty(
                    description: "The absolute path to the file."
                ),
                "targetPath": FileToolParameterSchemaBuilder.pathProperty(
                    description: "Deprecated alias for path. Use path instead."
                ),
                "old_text": FileToolParameterSchemaBuilder.pathProperty(
                    description: "The exact text to find and replace. Must match exactly including whitespace."
                ),
                "new_text": FileToolParameterSchemaBuilder.pathProperty(
                    description: "The new text to replace the old text with."
                ),
                "mode": FileToolParameterSchemaBuilder.modeProperty(),
                "patch_set_id": FileToolParameterSchemaBuilder.patchSetIdProperty()
            ],
            required: ["path", "old_text", "new_text"]
        )
    }

    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol

    private func resolvedPath(from arguments: [String: Any]) throws -> String {
        let candidates: [Any?] = [
            arguments["path"],
            arguments["targetPath"],
            arguments["target_path"],
            arguments["file_path"],
            arguments["file"],
            arguments["target"]
        ]

        let path = candidates
            .compactMap { $0 as? String }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        guard let path else {
            let keys = arguments.keys.sorted().joined(separator: ", ")
            throw AppError.aiServiceError(
                "Missing 'path' argument for replace_in_file. Provided keys: [\(keys)]. " +
                    "Fix: include a non-empty file path. Preferred key: 'path'. " +
                    "Accepted aliases: targetPath, target_path, file_path, file, target. Example:\n" +
                    "{\n  \"path\": \"src/App.css\",\n  \"old_text\": " +
                    "\".old { color: red; }\",\n  \"new_text\": \".old { color: blue; }\"\n}"
            )
        }

        return path
    }

    private func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String else {
            let keys = arguments.keys.sorted().joined(separator: ", ")
            throw AppError.aiServiceError(
                "Missing '\(key)' argument for replace_in_file. Provided keys: [\(keys)]. "
                    + "Fix: include a non-empty '\(key)' value. Example:\n"
                    + "{\n  \"path\": \"src/App.css\",\n  \"\(key)\": \".old { color: blue; }\"\n}"
            )
        }
        return value
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        let path = try resolvedPath(from: arguments)
        let oldText = try requiredString("old_text", in: arguments)
        let newText = try requiredString("new_text", in: arguments)

        let context = ToolInvocationContext.from(arguments: arguments)
        let mode = context.mode
        let toolCallId = context.toolCallId
        let patchSetId = context.patchSetId

        let url = try pathValidator.validateAndResolve(path)
        let relativePath = pathValidator.relativePath(for: url)
        let content = try fileSystemService.readFile(at: url)

        if !content.contains(oldText) {
            return "Error: Could not find the specified old_text in the file. Make sure it matches exactly."
        }

        let newContent = content.replacingOccurrences(of: oldText, with: newText)

        if mode == "propose" {
            try await FileToolProposalStager.stageWrite(
                patchSetId: patchSetId,
                toolCallId: toolCallId,
                relativePath: relativePath,
                content: newContent
            )
            await AIToolTraceLogger.shared.log(type: "fs.replace_in_file_proposed", data: [
                "path": relativePath,
                "patchSetId": patchSetId
            ])
            return FileToolProposalStager.proposedReplaceMessage(relativePath: relativePath, patchSetId: patchSetId)
        }

        await AIToolTraceLogger.shared.log(type: "fs.replace_in_file", data: [
            "path": relativePath
        ])
        try fileSystemService.writeFile(content: newContent, to: url)
        Task { @MainActor in
            eventBus.publish(FileModifiedEvent(url: url))
        }

        return "Successfully replaced content in \(relativePath)"
    }
}
