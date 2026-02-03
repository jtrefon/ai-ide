import Foundation

/// Search symbols in the Codebase Index.
struct IndexSearchSymbolsTool: AITool {
    let name = "index_search_symbols"
    let description = "Search for symbols (classes, functions, etc.) in the Codebase Index. " +
        "Use to locate relevant files/definitions efficiently."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Substring of the symbol name to search for."
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max results (default 50, max 200)."
                ]
            ],
            "required": ["query"]
        ]
    }

    let index: CodebaseIndexProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw AppError.aiServiceError("Missing 'query' argument for index_search_symbols")
        }
        let limit = max(1, min(200, arguments["limit"] as? Int ?? 50))

        let results = try await index.searchSymbolsWithPaths(nameLike: query, limit: limit)
        if results.isEmpty {
            return "No symbols found."
        }

        let lines = results.map { result in
            let symbol = result.symbol
            if let path = result.filePath {
                return "[\(symbol.kind.rawValue)] \(symbol.name) (\(path):\(symbol.lineStart)-\(symbol.lineEnd))"
            }
            return "[\(symbol.kind.rawValue)] \(symbol.name) (lines \(symbol.lineStart)-\(symbol.lineEnd))"
        }
        return lines.joined(separator: "\n")
    }
}
