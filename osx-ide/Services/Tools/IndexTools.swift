//
//  IndexTools.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

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

        return matches.map { m in
            if let score = m.qualityScore {
                let scoreText = String(format: "%.2f", score)
                return "\(m.path)  (ai_enriched=\(m.aiEnriched), quality_score=\(scoreText))"
            }
            return "\(m.path)  (ai_enriched=\(m.aiEnriched))"
        }.joined(separator: "\n")
    }
}

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
            let s = result.symbol
            if let path = result.filePath {
                return "[\(s.kind.rawValue)] \(s.name) (\(path):\(s.lineStart)-\(s.lineEnd))"
            }
            return "[\(s.kind.rawValue)] \(s.name) (lines \(s.lineStart)-\(s.lineEnd))"
        }
        return lines.joined(separator: "\n")
    }
}
