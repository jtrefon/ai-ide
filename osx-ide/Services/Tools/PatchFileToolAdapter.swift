import Foundation

/// Adapter that wraps PatchFileTool (v2 ToolDefinition/ToolFeedback)
/// into the old AITool protocol so it works with the proven ToolLoopHandler.
///
/// This is the BRIDGE between architectures: v2 tool logic → old execution pipeline.
struct PatchFileToolAdapter: AITool {
    let inner = PatchFileTool()
    let projectRoot: URL

    let name = "patch_file"
    let description = "Edit an existing file by line range. Preferred for all edits — surgical, precise, context-efficient. Read the file first for line numbers."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Absolute or project-relative path to the file to patch."
                ],
                "start_line": [
                    "type": "integer",
                    "description": "1-based line where replacement begins."
                ],
                "end_line": [
                    "type": "integer",
                    "description": "1-based line where replacement ends (inclusive). Set = start_line for single-line edits."
                ],
                "new_content": [
                    "type": "string",
                    "description": "Replacement content for the specified line range."
                ]
            ],
            "required": ["path", "start_line", "end_line", "new_content"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        // Convert old ToolArguments to v2 ToolExecutionRequest
        let raw = arguments.raw
        let path = raw["path"] as? String ?? ""
        let startLine = (raw["start_line"] as? Int) ?? 0
        let endLine = (raw["end_line"] as? Int) ?? 0
        let newContent = raw["new_content"] as? String ?? ""

        let req = ToolExecutionRequest(
            toolName: name,
            arguments: [
                "path": .string(path),
                "start_line": .integer(startLine),
                "end_line": .integer(endLine),
                "new_content": .string(newContent)
            ],
            context: ExecutionContext.coder(cid: "adapter", tid: UUID().uuidString, root: projectRoot)
        )

        let feedback = try await inner.exec(request: req)

        // Format ToolFeedback as string for the old system
        return ToolFeedbackFormatter().format(feedback)
    }
}
