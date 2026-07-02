import Foundation

/// Adapter that wraps PatchFileTool (v2 ToolDefinition/ToolFeedback)
/// into the old AITool protocol so it works with the proven ToolLoopHandler.
///
/// This is the BRIDGE between architectures: v2 tool logic → old execution pipeline.
struct PatchFileToolAdapter: AITool {
    let inner = PatchFileTool()

    let name = "patch_file"
    let description = "Apply a targeted edit by line range - surgical, precise, context-efficient. WHAT: Replaces a range of lines in an existing file with new content. More reliable than replace_in_file because it uses line numbers instead of exact text matching. WHEN: Use for ALL edits to existing files. Do NOT use write_file for edits. HOW: path (required) - absolute or project-relative path. start_line (required, int) - 1-based line where replacement begins. end_line (required, int) - 1-based line where replacement ends (inclusive). Set equal to start_line for single-line edits. new_content (required, string) - the replacement content for the line range. Read the file first with read_file to get line numbers. OUTPUT: Returns a diff-like confirmation showing what changed."

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
            context: ExecutionContext.coder(cid: "adapter", tid: UUID().uuidString, root: URL(fileURLWithPath: "/"))
        )

        let feedback = try await inner.exec(request: req)

        // Format ToolFeedback as string for the old system
        return ToolFeedbackFormatter().format(feedback)
    }
}
