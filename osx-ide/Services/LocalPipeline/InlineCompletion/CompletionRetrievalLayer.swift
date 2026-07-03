import Foundation

@MainActor
protocol CompletionRetrieving {
    func retrieveContext(
        for snapshot: InlineCompletionEditorSnapshot,
        request: CompletionContextPayload,
        settings: InlineCompletionSettings,
        reduceWorkload: Bool
    ) async -> [String]
}

@MainActor
final class CompletionRetrievalLayer: CompletionRetrieving {
    private let projectRootProvider: () -> URL?
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let cache = CompletionCache()

    init(
        projectRootProvider: @escaping () -> URL?,
        codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?
    ) {
        self.projectRootProvider = projectRootProvider
        self.codebaseIndexProvider = codebaseIndexProvider
    }

    func retrieveContext(
        for snapshot: InlineCompletionEditorSnapshot,
        request: CompletionContextPayload,
        settings: InlineCompletionSettings,
        reduceWorkload: Bool
    ) async -> [String] {
        guard settings.retrievalEnabled else { return [] }
        guard let index = codebaseIndexProvider() else { return [] }

        let key = cacheKey(for: snapshot, symbols: request.symbols, reduceWorkload: reduceWorkload)
        if let cached = cache.value(forKey: key) {
            return cached
        }

        var lines: [String] = []
        if let sameFileContext = readSameFileContext(snapshot: snapshot, index: index) {
            lines.append("[same-file]")
            lines.append(sameFileContext)
        }

        let symbolLines = await symbolContextLines(from: request.symbols, index: index, limit: reduceWorkload ? 3 : 5)
        lines.append(contentsOf: symbolLines)

        if !reduceWorkload {
            let semantic = await semanticContextLines(query: String(request.prefix.suffix(320)), index: index)
            lines.append(contentsOf: semantic)
        }

        let limited = Array(lines.prefix(reduceWorkload ? 6 : 10))
        cache.insert(limited, forKey: key)
        return limited
    }

    private func cacheKey(
        for snapshot: InlineCompletionEditorSnapshot,
        symbols: [String],
        reduceWorkload: Bool
    ) -> String {
        let symbolKey = symbols.prefix(4).joined(separator: "|")
        return [
            snapshot.filePath ?? "<untitled>",
            String(snapshot.cursorPosition),
            symbolKey,
            reduceWorkload ? "reduced" : "full"
        ].joined(separator: "::")
    }

    private func readSameFileContext(
        snapshot: InlineCompletionEditorSnapshot,
        index: CodebaseIndexProtocol
    ) -> String? {
        guard let filePath = snapshot.filePath,
              let projectRoot = projectRootProvider() else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL
        let rootURL = projectRoot.standardizedFileURL
        guard fileURL.path.hasPrefix(rootURL.path) else { return nil }

        let relativePath = fileURL.relativeTo(rootURL)
        let line = snapshot.buffer.prefix(snapshot.cursorPosition).filter { $0 == "\n" }.count + 1
        return try? index.readIndexedFile(path: relativePath, startLine: max(1, line - 12), endLine: line + 6)
    }

    private func symbolContextLines(
        from symbols: [String],
        index: CodebaseIndexProtocol,
        limit: Int
    ) async -> [String] {
        var lines: [String] = []
        for symbol in symbols.prefix(4) {
            guard let matches = try? await index.searchSymbolsWithPaths(nameLike: symbol, limit: limit),
                  !matches.isEmpty else {
                continue
            }
            for match in matches.prefix(2) {
                let location = match.filePath.map { "\($0):\(match.symbol.lineStart)" } ?? "unknown"
                lines.append("[symbol] \(match.symbol.name) \(location)")
            }
        }
        return Array(lines.prefix(limit))
    }

    private func semanticContextLines(query: String, index: CodebaseIndexProtocol) async -> [String] {
        []
    }
}

