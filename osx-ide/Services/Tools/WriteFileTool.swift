//
//  WriteFileTool.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation

/// Write content to a file at the specified path. Overwrites if it exists.
struct WriteFileTool: AITool {
    let name = "write_file"
    let description = "Write content to a file at the specified path. Overwrites if it exists."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The absolute path to the file."
                ],
                "content": [
                    "type": "string",
                    "description": "The content to write to the file."
                ],
                "mode": [
                    "type": "string",
                    "description": "One of: apply, propose. Default: apply.",
                    "enum": ["apply", "propose"]
                ],
                "patch_set_id": [
                    "type": "string",
                    "description": "Patch set identifier to stage into when mode=propose."
                ]
            ],
            "required": ["path", "content"]
        ]
    }
    
    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let eventBus: EventBusProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let path = arguments["path"] as? String, 
                !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let keys = arguments.keys.sorted().joined(separator: ", ")
            throw AppError.aiServiceError(
                "Missing 'path' argument for write_file. Provided keys: [\(keys)]. "
                    + "Fix: include a non-empty path (absolute or project-root-relative). Example:\n"
                    + "{\n  \"path\": \"src/App.css\",\n  \"content\": \"/* ... */\"\n}"
            )
        }
        guard let content = arguments["content"] as? String else {
            throw AppError.aiServiceError("Missing 'content' argument for write_file")
        }

        let context = ToolInvocationContext.from(arguments: arguments)
        let mode = context.mode
        let toolCallId = context.toolCallId
        let patchSetId = context.patchSetId

        let url = try pathValidator.validateAndResolve(path)
        let relativePath = pathValidator.relativePath(for: url)

        if mode == "propose" {
            try await PatchSetStore.shared.stageWrite(
                patchSetId: patchSetId,
                toolCallId: toolCallId,
                relativePath: relativePath,
                content: content
            )
            await AIToolTraceLogger.shared.log(type: "fs.write_file_proposed", data: [
                "path": relativePath,
                "bytes": content.utf8.count,
                "patchSetId": patchSetId
            ])
            return "Proposed write to \(relativePath) (patch_set_id=\(patchSetId))."
        }

        await AIToolTraceLogger.shared.log(type: "fs.write_file", data: [
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
        return "Successfully wrote to \(relativePath)"
    }
}
