import Foundation

/// Search for a literal substring in indexed files.
/// Returns matches as: relative/path:line: snippet
struct IndexSearchTextTool: AITool {
    let name = "index_search_text"
    let description = "Search for a literal substring across indexed files only (authoritative set). " +
        "Returns matches formatted as 'path:line: snippet'."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Literal substring to search for (case-sensitive)."
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max matches to return (default 100, max 500)."
                ]
            ],
            "required": ["pattern"]
        ]
    }

    let index: CodebaseIndexProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let pattern = arguments["pattern"] as? String, !pattern.isEmpty else {
            throw AppError.aiServiceError("Missing 'pattern' argument for index_search_text")
        }
        let limit = max(1, min(500, arguments["limit"] as? Int ?? 100))

        let results = try await index.searchIndexedText(pattern: pattern, limit: limit)
        return results.isEmpty ? "No matches found in indexed files." : results.joined(separator: "\n")
    }
}
