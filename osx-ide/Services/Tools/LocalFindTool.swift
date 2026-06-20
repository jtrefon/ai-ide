import Foundation

/// The ONLY search/find tool available to local models.
/// All search methods use the codebase index (vector, symbol, FTS, path LIKE).
/// No filesystem grep — too slow for large projects and would time out.
struct LocalFindTool: AITool {
    let name = "find"
    let description = "Find files, classes, functions, variables, or text in the project. " +
        "Uses the codebase index for vector search, symbol lookup, full-text search, " +
        "and path matching. Returns ALL matches grouped by file with type and location. " +
        "This is the ONLY search tool — use it for ANY code discovery task."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "phrase": [
                    "type": "string",
                    "description": "The search phrase — can be a file name, class name, function name, variable, or any text pattern."
                ]
            ],
            "required": ["phrase"]
        ]
    }

    let index: CodebaseIndexProtocol?
    let projectRoot: URL

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        guard let phrase = raw["phrase"] as? String else {
            return "Missing 'phrase' argument."
        }

        guard let index else {
            return "The codebase index is still building. Please wait a moment and try again."
        }

        var entries: [SearchEntry] = []
        let maxResults = 100

        // 1. Vector semantic search (conceptually relevant code)
        if let chunks = try? await index.getRelevantCodeChunks(userInput: phrase, limit: 20) {
            for chunk in chunks {
                let ctx = String(chunk.snippet.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
                entries.append(SearchEntry(file: chunk.filePath, line: chunk.lineStart, matchType: "semantic", context: ctx))
            }
        }

        // 2. Symbol search (classes, functions, variables)
        if entries.count < maxResults {
            if let symbols = try? await index.searchSymbolsWithPaths(nameLike: phrase, limit: 30) {
                for sym in symbols {
                    let kind = classify(sym.symbol.kind)
                    let path = sym.filePath ?? "unknown"
                    entries.append(SearchEntry(file: path, line: sym.symbol.lineStart, matchType: kind, context: "\(kind) \(sym.symbol.name)"))
                }
            }
        }

        // 3. Full-text search via index FTS5 (fast, sub-millisecond)
        if entries.count < maxResults {
            if let textMatches = try? await index.searchIndexedText(pattern: phrase, limit: 30) {
                for match in textMatches {
                    let parts = match.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                    if parts.count >= 3 {
                        entries.append(SearchEntry(
                            file: String(parts[0]),
                            line: Int(parts[1]) ?? 0,
                            matchType: "reference",
                            context: String(parts[2]).trimmingCharacters(in: .whitespaces).prefix(100).description
                        ))
                    }
                }
            }
        }

        // 4. Filename match via index (path LIKE query)
        if entries.count < maxResults {
            let fileMatches = try? await index.listIndexedFiles(matching: phrase, limit: 20, offset: 0)
            for filePath in fileMatches ?? [] {
                let name = (filePath as NSString).lastPathComponent
                entries.append(SearchEntry(file: filePath, line: 0, matchType: "filename", context: name))
            }
        }

        guard !entries.isEmpty else {
            return "No matches found for '\(phrase)' in the indexed project files."
        }

        return format(entries: entries, phrase: phrase)
    }

    // MARK: - Formatting

    private func format(entries: [SearchEntry], phrase: String) -> String {
        let grouped = Dictionary(grouping: entries) { $0.file }.sorted { $0.key < $1.key }
        var output = "Found \(entries.count) match(s) for \"\(phrase)\":\n\n"
        for (file, fileEntries) in grouped {
            output += "📄 \(file)\n"
            for e in fileEntries.prefix(10) {
                let info = e.line > 0 ? "L\(e.line) " : ""
                output += "  \(info)[\(e.matchType)] \(e.context)\n"
            }
            if fileEntries.count > 10 { output += "  ... +\(fileEntries.count - 10) more\n" }
            output += "\n"
        }
        return output
    }

    private func classify(_ kind: SymbolKind) -> String {
        switch kind {
        case .class: return "class"; case .struct: return "struct"
        case .enum: return "enum"; case .protocol: return "interface"
        case .extension: return "extension"; case .function: return "function"
        case .variable: return "variable"; case .initializer: return "initializer"
        case .unknown: return "symbol"
        }
    }

    private struct SearchEntry: Sendable {
        let file: String; let line: Int; let matchType: String; let context: String
    }
}
