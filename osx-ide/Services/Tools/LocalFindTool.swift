import Foundation

/// The ONLY search/find tool available to local models.
/// All searches use the codebase index (FTS5 + symbol tables + path LIKE).
/// Each method has a short timeout; if the index is busy, returns
/// available results immediately rather than hanging.
struct LocalFindTool: AITool {
    let name = "find"
    let description = "Find files, classes, functions, variables, or text in the project. " +
        "Searches the indexed project files using full-text search, symbol lookup, " +
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

        // Run all search methods concurrently.
        // Each has a 5-second timeout built in.
        async let symbolsTask = searchSymbols(index: index, phrase: phrase, limit: 20)
        async let ftsTask = searchFTS(index: index, phrase: phrase, limit: 20)
        async let pathsTask = searchPaths(index: index, phrase: phrase, limit: 10)

        let symbolResults = await symbolsTask
        let ftsResults = await ftsTask
        let pathResults = await pathsTask

        var entries: [SearchEntry] = []
        entries.append(contentsOf: symbolResults)
        entries.append(contentsOf: ftsResults)
        entries.append(contentsOf: pathResults)

        guard !entries.isEmpty else {
            return "No matches found for '\(phrase)' in the indexed project files."
        }
        return format(entries: entries, phrase: phrase)
    }

    // MARK: - Index search methods (each with timeout)

    private func searchSymbols(index: CodebaseIndexProtocol, phrase: String, limit: Int) async -> [SearchEntry] {
        do {
            return try await withThrowingTaskGroup(of: [SearchEntry].self) { group in
                group.addTask {
                    let symbols = try await index.searchSymbolsWithPaths(nameLike: phrase, limit: limit)
                    return symbols.map { sym in
                        let kind = Self.symbolKindLabel(sym.symbol.kind)
                        return SearchEntry(
                            file: sym.filePath ?? "unknown",
                            line: sym.symbol.lineStart,
                            matchType: kind,
                            context: "\(kind) \(sym.symbol.name)"
                        )
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return []
                }
                defer { group.cancelAll() }
                for try await result in group {
                    if !result.isEmpty { return result }
                }
                return []
            }
        } catch {
            return []
        }
    }

    private func searchFTS(index: CodebaseIndexProtocol, phrase: String, limit: Int) async -> [SearchEntry] {
        do {
            return try await withThrowingTaskGroup(of: [SearchEntry].self) { group in
                group.addTask {
                    let matches = try await index.searchIndexedText(pattern: phrase, limit: limit)
                    return matches.compactMap { match -> SearchEntry? in
                        let parts = match.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                        guard parts.count >= 3 else { return nil }
                        return SearchEntry(
                            file: String(parts[0]),
                            line: Int(parts[1]) ?? 0,
                            matchType: "reference",
                            context: String(parts[2]).trimmingCharacters(in: .whitespaces).prefix(100).description
                        )
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return []
                }
                defer { group.cancelAll() }
                for try await result in group {
                    if !result.isEmpty { return result }
                }
                return []
            }
        } catch {
            return []
        }
    }

    private func searchPaths(index: CodebaseIndexProtocol, phrase: String, limit: Int) async -> [SearchEntry] {
        do {
            return try await withThrowingTaskGroup(of: [SearchEntry].self) { group in
                group.addTask {
                    let files = try await index.listIndexedFiles(matching: phrase, limit: limit, offset: 0)
                    return files.map { path in
                        SearchEntry(
                            file: path,
                            line: 0,
                            matchType: "filename",
                            context: (path as NSString).lastPathComponent
                        )
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return []
                }
                defer { group.cancelAll() }
                for try await result in group {
                    if !result.isEmpty { return result }
                }
                return []
            }
        } catch {
            return []
        }
    }

    // MARK: - Formatting

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

    private static func symbolKindLabel(_ kind: SymbolKind) -> String {
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
