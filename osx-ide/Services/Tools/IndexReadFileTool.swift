import Foundation

/// Read a file via Codebase Index with stable, line-numbered output.
/// Designed for patch-style edits (small focused reads using ranges).
struct IndexReadFileTool: AITool {
    let name = "index_read_file"
    let description = "Read a file (line-numbered) via the Codebase Index. Provide relative path " +
        "and optional start_line/end_line to fetch only a small range for patch-based edits."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Path relative to project root (preferred)."
                ],
                "start_line": [
                    "type": "integer",
                    "description": "1-based start line (optional)."
                ],
                "end_line": [
                    "type": "integer",
                    "description": "1-based end line (optional)."
                ]
            ],
            "required": ["path"]
        ]
    }

    let index: CodebaseIndexProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for index_read_file")
        }
        let startLine = arguments["start_line"] as? Int
        let endLine = arguments["end_line"] as? Int

        return try await index.readIndexedFile(path: path, startLine: startLine, endLine: endLine)
    }
}
