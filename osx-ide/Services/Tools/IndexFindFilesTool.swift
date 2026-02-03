import Foundation

/// Find files by name/path using the Codebase Index.
/// This is the preferred way to resolve "what file is X?" before any text search.
struct IndexFindFilesTool: AITool {
    let name = "index_find_files"
    let description = "Find files by name/path using the Codebase Index (paths only, not content). " +
        "Returns ranked matches and includes ai_enriched/quality_score metadata when available."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Filename, basename, or path substring " +
                        "(e.g. 'train_cli', 'DatabaseManager.swift', 'Services/Index')."
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max results (default 25, max 200)."
                ]
            ],
            "required": ["query"]
        ]
    }

    let index: CodebaseIndexProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let query = arguments["query"] as? String else {
            throw AppError.aiServiceError("Missing 'query' argument for index_find_files")
        }

        let limit = max(1, min(200, arguments["limit"] as? Int ?? 25))
        let matches = try await index.findIndexedFiles(query: query, limit: limit)
        if matches.isEmpty {
            return "No files found in index."
        }

        return matches.map { match in
            if let score = match.qualityScore {
                let scoreText = String(format: "%.2f", score)
                return "\(match.path)  (ai_enriched=\(match.aiEnriched), quality_score=\(scoreText))"
            }
            return "\(match.path)  (ai_enriched=\(match.aiEnriched))"
        }.joined(separator: "\n")
    }
}
