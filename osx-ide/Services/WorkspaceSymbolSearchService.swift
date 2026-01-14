import Foundation

struct WorkspaceSymbolLocation: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: SymbolKind
    let relativePath: String
    let line: Int
}

@MainActor
final class WorkspaceSymbolSearchService {
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let settingsStore: SettingsStore

    init(codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?) {
        self.codebaseIndexProvider = codebaseIndexProvider
        self.settingsStore = SettingsStore(userDefaults: .standard)
    }

    func search(
        query rawQuery: String,
        projectRoot: URL,
        currentFilePath: String?,
        currentContent: String?,
        currentLanguage: String?,
        limit: Int
    ) async -> [WorkspaceSymbolLocation] {
        let needle = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if needle.isEmpty {
            guard let currentFilePath, let currentContent, let currentLanguage else { return [] }
            guard let rel = Self.relativePath(
                projectRoot: projectRoot,
                absolutePath: currentFilePath
            ) else { return [] }
            let parsed = parseSymbols(
                language: currentLanguage,
                content: currentContent,
                resourceId: URL(fileURLWithPath: currentFilePath).absoluteString
            )
            return parsed.prefix(limit).map { sym in
                WorkspaceSymbolLocation(
                    id: "\(rel):\(sym.line):\(sym.kind.rawValue):\(sym.name)",
                    name: sym.name,
                    kind: sym.kind,
                    relativePath: rel,
                    line: sym.line
                )
            }
        }

        if let index = codebaseIndexProvider(),
           settingsStore.bool(forKey: AppConstants.Storage.codebaseIndexEnabledKey, default: true),
           let matches = try? await index.searchSymbolsWithPaths(nameLike: needle, limit: max(1, min(200, limit))) {
            var out: [WorkspaceSymbolLocation] = []
            out.reserveCapacity(min(limit, matches.count))

            for match in matches {
                guard let filePath = match.filePath else { continue }
                guard let rel = Self.relativePath(projectRoot: projectRoot, absolutePath: filePath) else { continue }

                let symbol = match.symbol
                out.append(
                    WorkspaceSymbolLocation(
                        id: "\(rel):\(symbol.lineStart):\(symbol.kind.rawValue):\(symbol.name)",
                        name: symbol.name,
                        kind: symbol.kind,
                        relativePath: rel,
                        line: max(1, symbol.lineStart)
                    )
                )

                if out.count >= limit { break }
            }

            return sort(out, query: needle)
        }

        // Fallback: current buffer only.
        guard let currentFilePath, let currentContent, let currentLanguage else { return [] }
        guard let rel = Self.relativePath(projectRoot: projectRoot, absolutePath: currentFilePath) else { return [] }

        let parsed = parseSymbols(
            language: currentLanguage,
            content: currentContent,
            resourceId: URL(fileURLWithPath: currentFilePath).absoluteString
        )
        let filtered = parsed.filter { $0.name.lowercased().contains(needle.lowercased()) }

        let limited = filtered.prefix(limit).map { sym in
            WorkspaceSymbolLocation(
                id: "\(rel):\(sym.line):\(sym.kind.rawValue):\(sym.name)",
                name: sym.name,
                kind: sym.kind,
                relativePath: rel,
                line: sym.line
            )
        }

        return sort(Array(limited), query: needle)
    }

    private func parseSymbols(
        language: String,
        content: String,
        resourceId: String
    ) -> [(name: String, kind: SymbolKind, line: Int)] {
        if let codeLanguage = CodeLanguage(rawValue: language.lowercased()),
           let module = LanguageModuleManager.shared.getModule(for: codeLanguage) {
            return module.symbolExtractor
                .extractSymbols(content: content, resourceId: resourceId)
                .map { (name: $0.name, kind: $0.kind, line: $0.lineStart) }
        }

        return []
    }

    private func sort(_ items: [WorkspaceSymbolLocation], query: String) -> [WorkspaceSymbolLocation] {
        let needle = query.lowercased()

        func score(_ name: String) -> Int {
            let lowercasedName = name.lowercased()
            if lowercasedName == needle { return 1_000 }
            if lowercasedName.hasPrefix(needle) { return 700 }
            if lowercasedName.contains(needle) { return 500 }
            return 0
        }

        return items.sorted { left, right in
            let sa = score(left.name)
            let sb = score(right.name)
            if sa != sb { return sa > sb }
            if left.relativePath != right.relativePath { return left.relativePath < right.relativePath }
            if left.line != right.line { return left.line < right.line }
            return left.name < right.name
        }
    }

    static func relativePath(projectRoot: URL, absolutePath: String) -> String? {
        let root = projectRoot.standardizedFileURL.path
        let abs = URL(fileURLWithPath: absolutePath).standardizedFileURL.path
        guard abs.hasPrefix(root + "/") else { return nil }
        return String(abs.dropFirst(root.count + 1))
    }
}
