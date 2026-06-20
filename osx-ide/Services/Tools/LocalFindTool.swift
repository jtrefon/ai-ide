import Foundation

/// The ONLY search/find tool available to local models.
/// Runs all search methods internally and returns a concise summary.
/// No other search/list/discovery tools are needed.
struct LocalFindTool: AITool {
    let name = "find"
    let description = "Find files, classes, functions, variables, or text in the project. " +
        "Runs vector search, symbol lookup, full-text search, grep, and filename matching " +
        "internally. Returns ALL matches grouped by file with type and location. " +
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
        let lowerPhrase = phrase.lowercased()

        var entries: [SearchEntry] = []
        let maxResults = 100

        // 1. Vector semantic search
        if let index {
            if let chunks = try? await index.getRelevantCodeChunks(userInput: phrase, limit: 20) {
                for chunk in chunks {
                    let ctx = String(chunk.snippet.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
                    entries.append(SearchEntry(file: chunk.filePath, line: chunk.lineStart, matchType: "semantic", context: ctx))
                }
            }
        }

        // 2. Symbol search
        if let index {
            if let symbols = try? await index.searchSymbolsWithPaths(nameLike: phrase, limit: 30) {
                for sym in symbols {
                    let kind = classify(sym.symbol.kind)
                    let path = sym.filePath ?? "unknown"
                    entries.append(SearchEntry(file: path, line: sym.symbol.lineStart, matchType: kind, context: "\(kind) \(sym.symbol.name)"))
                }
            }
        }

        // 3. Full-text search via index
        if entries.count < maxResults, let index {
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

        // 4. Grep filesystem
        if entries.count < maxResults {
            let grepResults = try await grepFilesystem(query: lowerPhrase, maxResults: maxResults - entries.count)
            entries.append(contentsOf: grepResults)
        }

        // 5. Filename match
        if entries.count < maxResults {
            let fileResults = findFilesByName(query: lowerPhrase, maxResults: maxResults - entries.count)
            entries.append(contentsOf: fileResults)
        }

        guard !entries.isEmpty else {
            return "No matches found for '\(phrase)'."
        }

        return format(entries: entries, phrase: phrase)
    }

    // MARK: - Search methods

    private func grepFilesystem(query: String, maxResults: Int) async throws -> [SearchEntry] {
        var results: [SearchEntry] = []
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }
        while let fileURL = enumerator.nextObject() as? URL {
            if results.count >= maxResults { break }
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { if ToolFileExclusion.isExcluded(url: fileURL) { enumerator.skipDescendants() }; continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for (i, line) in content.components(separatedBy: .newlines).enumerated() {
                if results.count >= maxResults { break }
                if line.lowercased().contains(query) {
                    results.append(SearchEntry(file: relPath(fileURL), line: i + 1, matchType: "reference", context: line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return results
    }

    private func findFilesByName(query: String, maxResults: Int) -> [SearchEntry] {
        var results: [SearchEntry] = []
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }
        while let fileURL = enumerator.nextObject() as? URL {
            if results.count >= maxResults { break }
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { if ToolFileExclusion.isExcluded(url: fileURL) { enumerator.skipDescendants() }; continue }
            if fileURL.lastPathComponent.lowercased().contains(query) {
                results.append(SearchEntry(file: relPath(fileURL), line: 0, matchType: "filename", context: fileURL.lastPathComponent))
            }
        }
        return results
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

    private func relPath(_ url: URL) -> String {
        let root = projectRoot.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(root + "/") { return String(full.dropFirst(root.count + 1)) }
        return full
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
