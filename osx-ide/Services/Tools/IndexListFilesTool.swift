import Foundation

/// List files known to the Codebase Index.
/// Use for file discovery instead of scanning the filesystem.
struct IndexListFilesTool: AITool {
    let name = "index_list_files"
    let description = "List files known to the Codebase Index (authoritative). Use for file discovery " +
        "instead of scanning the filesystem. Supports optional path substring filtering and pagination."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Optional case-insensitive substring filter on path " +
                        "(e.g. 'Services/Index', 'DatabaseManager')."
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max results (default 50, max 500)."
                ],
                "offset": [
                    "type": "integer",
                    "description": "Offset for pagination (default 0)."
                ]
            ],
            "required": []
        ]
    }

    let index: CodebaseIndexProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        let query = (arguments["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(500, arguments["limit"] as? Int ?? 50))
        let offset = max(0, arguments["offset"] as? Int ?? 0)

        let results = try await index.listIndexedFiles(
            matching: query?.isEmpty == true ? nil : query,
            limit: limit,
            offset: offset
        )
        return results.isEmpty ? "No indexed files found." : results.joined(separator: "\n")
    }
}
