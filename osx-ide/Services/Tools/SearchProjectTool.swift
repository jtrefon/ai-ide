import Foundation

/// Comprehensive project search tool.
/// Combines index symbol search, full-text search, grep, and filename matching
/// into a single call. Returns ALL occurrences of a query with type, location, and context.
struct SearchProjectTool: AITool {
    let name = "search_project"
    let description = "THE PRIMARY search tool for ANY code search task. " +
        "Finds classes, functions, variables, files, and text patterns. " +
        "Uses semantic search (vector similarity), symbol lookup, full-text index, " +
        "and filesystem grep — automatically picks the best method. " +
        "Returns results grouped by file with match type and line numbers. " +
        "ALWAYS use this first for code search instead of find_file or grep."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "The search term (class name, function name, variable, import, etc.). Case-insensitive."
                ],
                "max_results": [
                    "type": "integer",
                    "description": "Maximum results to return (default 50, max 200)."
                ]
            ],
            "required": ["query"]
        ]
    }

    let index: CodebaseIndexProtocol?
    let projectRoot: URL

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        guard let query = raw["query"] as? String else {
            return "Missing 'query' argument."
        }
        let maxResults = min(200, max(1, raw["max_results"] as? Int ?? 50))
        let lowerQuery = query.lowercased()

        var entries: [SearchEntry] = []

        // 1. Vector semantic search via index (best for conceptual relevance)
        if let index {
            if let chunks = try? await index.getRelevantCodeChunks(userInput: query, limit: maxResults / 2) {
                for chunk in chunks {
                    entries.append(SearchEntry(
                        file: chunk.filePath,
                        line: chunk.lineStart,
                        matchType: "semantic",
                        context: chunk.snippet.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120).description
                    ))
                }
            }
        }

        // 2. Symbol search via index (authoritative for code structure)
        if let index {
            if let symbols = try? await index.searchSymbolsWithPaths(nameLike: query, limit: maxResults) {
                for symbolResult in symbols {
                    let kind = classifySymbolKind(symbolResult.symbol.kind)
                    let filePath = symbolResult.filePath ?? "unknown"
                    let line = symbolResult.symbol.lineStart
                    entries.append(SearchEntry(
                        file: filePath,
                        line: line,
                        matchType: kind,
                        context: "\(kind) \(symbolResult.symbol.name)"
                    ))
                }
            }

            // 2. Full-text search via index
            if entries.count < maxResults {
                let remaining = maxResults - entries.count
                if let textMatches = try? await index.searchIndexedText(pattern: query, limit: remaining) {
                    for match in textMatches {
                        // Format: file:line: snippet
                        let parts = match.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                        if parts.count >= 3 {
                            let file = String(parts[0])
                            let line = Int(parts[1]) ?? 0
                            let context = String(parts[2]).trimmingCharacters(in: .whitespaces)
                            entries.append(SearchEntry(file: file, line: line, matchType: "reference", context: context))
                        }
                    }
                }
            }
        }

        // 3. Filesystem grep (fallback / supplement)
        if entries.count < maxResults {
            let grepResults = try await grepFilesystem(query: lowerQuery, maxResults: maxResults - entries.count)
            entries.append(contentsOf: grepResults)
        }

        // 4. Filename search (supplement)
        if entries.count < maxResults {
            let fileResults = findFilesByName(query: lowerQuery, maxResults: maxResults - entries.count)
            entries.append(contentsOf: fileResults)
        }

        guard !entries.isEmpty else {
            return "No matches found for '\(query)'."
        }

        return formatResults(entries: entries, query: query)
    }

    // MARK: - Search Methods

    private func grepFilesystem(query: String, maxResults: Int) async throws -> [SearchEntry] {
        var results: [SearchEntry] = []
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        while let fileURL = enumerator.nextObject() as? URL {
            if results.count >= maxResults { break }
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if ToolFileExclusion.isExcluded(url: fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                if results.count >= maxResults { break }
                if line.lowercased().contains(query) {
                    let relPath = relativePath(fileURL)
                    let ctx = line.trimmingCharacters(in: .whitespaces)
                    results.append(SearchEntry(file: relPath, line: i + 1, matchType: "reference", context: ctx))
                }
            }
        }
        return results
    }

    private func findFilesByName(query: String, maxResults: Int) -> [SearchEntry] {
        var results: [SearchEntry] = []
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        while let fileURL = enumerator.nextObject() as? URL {
            if results.count >= maxResults { break }
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if ToolFileExclusion.isExcluded(url: fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }
            let name = fileURL.lastPathComponent.lowercased()
            if name.contains(query) {
                results.append(SearchEntry(
                    file: relativePath(fileURL),
                    line: 0,
                    matchType: "filename",
                    context: fileURL.lastPathComponent
                ))
            }
        }
        return results
    }

    // MARK: - Formatting

    private func formatResults(entries: [SearchEntry], query: String) -> String {
        let grouped = Dictionary(grouping: entries) { $0.file }
            .sorted { $0.key < $1.key }

        var output = "Found \(entries.count) occurrence(s) of \"\(query)\":\n\n"
        for (file, fileEntries) in grouped {
            output += "📄 \(file)\n"
            for entry in fileEntries.prefix(20) {
                let lineInfo = entry.line > 0 ? "L\(entry.line) " : ""
                output += "  \(lineInfo)[\(entry.matchType)] \(entry.context)\n"
            }
            if fileEntries.count > 20 {
                output += "  ... and \(fileEntries.count - 20) more matches in this file\n"
            }
            output += "\n"
        }
        return output
    }

    // MARK: - Helpers

    private func relativePath(_ url: URL) -> String {
        let root = projectRoot.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(root + "/") {
            return String(full.dropFirst(root.count + 1))
        }
        return full
    }

    private func classifySymbolKind(_ kind: SymbolKind) -> String {
        switch kind {
        case .class: return "class"
        case .struct: return "struct"
        case .enum: return "enum"
        case .protocol: return "interface"
        case .extension: return "extension"
        case .function: return "function"
        case .variable: return "variable"
        case .initializer: return "initializer"
        case .unknown: return "symbol"
        }
    }

    private struct SearchEntry: Sendable {
        let file: String
        let line: Int
        let matchType: String
        let context: String
    }
}
