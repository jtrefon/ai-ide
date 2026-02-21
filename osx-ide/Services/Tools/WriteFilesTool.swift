import Foundation
import Combine

/// Write content to multiple files (preferred for scaffolding a project)
struct WriteFilesTool: AITool {
    let name = "write_files"
    let description = "Write content to multiple files. Overwrites existing files. " +
        "Preferred for scaffolding multi-file changes in one operation."
    var parameters: [String: Any] {
        FileToolParameterSchemaBuilder.objectSchema(
            properties: [
                "files": [
                    "type": "array",
                    "description": "List of files to write.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "path": FileToolParameterSchemaBuilder.pathProperty(
                                description: "Absolute path or project-root-relative path to the file."
                            ),
                            "content": [
                                "type": "string",
                                "description": "Content to write to the file."
                            ]
                        ],
                        "required": ["path", "content"]
                    ]
                ],
                "mode": FileToolParameterSchemaBuilder.modeProperty(),
                "patch_set_id": FileToolParameterSchemaBuilder.patchSetIdProperty()
            ],
            required: ["files"]
        )
    }

    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol

    private struct WriteFileEntry {
        let url: URL
        let relativePath: String
        let content: String
    }

    private func resolvedWriteFileEntry(
        from entry: [String: Any]
    ) throws -> WriteFileEntry {
        guard let path = entry["path"] as? String else {
            throw AppError.aiServiceError(
                "Missing 'path' in a write_files entry"
            )
        }
        guard let content = entry["content"] as? String else {
            throw AppError.aiServiceError("Missing 'content' in a write_files entry")
        }

        let url = try pathValidator.validateAndResolve(path)
        let relativePath = pathValidator.relativePath(for: url)
        return WriteFileEntry(url: url, relativePath: relativePath, content: content)
    }

    private func applyWrite(url: URL, relativePath: String, content: String) async throws {
        try await FileToolWriteApplier.applyWrite(
            FileToolWriteApplier.ApplyWriteRequest(
                fileSystemService: fileSystemService,
                eventBus: eventBus,
                url: url,
                relativePath: relativePath,
                content: content,
                traceType: "fs.write_files_entry"
            )
        )
    }

    private func stageProposedWrite(
        patchSetId: String,
        toolCallId: String,
        relativePath: String,
        content: String
    ) async throws -> String {
        try await FileToolProposalStager.stageWriteAndProposedMessage(
            FileToolProposalStager.StageWriteAndMessageRequest(
                patchSetId: patchSetId,
                toolCallId: toolCallId,
                relativePath: relativePath,
                content: content,
                messageBuilder: FileToolProposalStager.proposedWriteMessage(relativePath:patchSetId:)
            )
        )
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        
        // Support both "files" array (preferred) and direct "path"/"content" (for compatibility with write_file)
        let files: [[String: Any]]
        
        if let filesArray = arguments["files"] as? [[String: Any]] {
            files = filesArray
        } else if let path = arguments["path"] as? String, let content = arguments["content"] as? String {
            // Allow single file via path/content for compatibility
            files = [["path": path, "content": content]]
        } else {
            throw AppError.aiServiceError(
                "Missing 'files' argument for write_files. " +
                "Either provide 'files' as an array of {path, content} objects, " +
                "or provide 'path' and 'content' directly for a single file."
            )
        }

        let context = ToolInvocationContext.from(arguments: arguments)
        let mode = context.mode
        let toolCallId = context.toolCallId
        let patchSetId = context.patchSetId

        if files.isEmpty {
            return "No files to write."
        }

        var results: [String] = []
        results.reserveCapacity(files.count)

        await AIToolTraceLogger.shared.log(
            type: mode == "propose" ? "fs.write_files_propose_start" : "fs.write_files_start",
            data: [
                "count": files.count,
                "patchSetId": patchSetId
            ]
        )

        for entry in files {
            let resolved = try resolvedWriteFileEntry(from: entry)
            if mode == "propose" {
                let message = try await stageProposedWrite(
                    patchSetId: patchSetId,
                    toolCallId: toolCallId,
                    relativePath: resolved.relativePath,
                    content: resolved.content
                )
                results.append(message)
                continue
            }

            try await applyWrite(url: resolved.url, relativePath: resolved.relativePath, content: resolved.content)
            results.append(resolved.relativePath)
        }

        await AIToolTraceLogger.shared.log(
            type: mode == "propose" ? "fs.write_files_propose_done" : "fs.write_files_done",
            data: [
                "count": results.count,
                "patchSetId": patchSetId
            ]
        )

        if mode == "propose" {
            return "Proposed \(results.count) file(s) (patch_set_id=\(patchSetId)):\n" + results.joined(separator: "\n")
        }
        return "Successfully wrote \(results.count) file(s):\n" + results.joined(separator: "\n")
    }
}
