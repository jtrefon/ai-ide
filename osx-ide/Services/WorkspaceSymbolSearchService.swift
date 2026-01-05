import Foundation

struct WorkspaceSymbolLocation: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: SymbolKind
    let relativePath: String
    let line: Int
}

enum WorkspaceSymbolParser {
    static func parse(language: String, content: String) -> [(name: String, kind: SymbolKind, line: Int)] {
        let normalized = language.lowercased()
        if normalized == "swift" {
            return parseSwift(content: content)
        }
        if normalized == "javascript" || normalized == "typescript" {
            return parseJSTS(content: content)
        }
        if normalized == "python" {
            return parsePython(content: content)
        }
        return []
    }

    private static func parseSwift(content: String) -> [(name: String, kind: SymbolKind, line: Int)] {
        // Intentionally simple patterns (MVP)
        let patterns: [(SymbolKind, NSRegularExpression)] = [
            (.class, try! NSRegularExpression(pattern: "^[\\t ]*class\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [.anchorsMatchLines])),
            (.struct, try! NSRegularExpression(pattern: "^[\\t ]*struct\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [.anchorsMatchLines])),
            (.enum, try! NSRegularExpression(pattern: "^[\\t ]*enum\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [.anchorsMatchLines])),
            (.protocol, try! NSRegularExpression(pattern: "^[\\t ]*protocol\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [.anchorsMatchLines])),
            (.extension, try! NSRegularExpression(pattern: "^[\\t ]*extension\\s+([A-Za-z_][A-Za-z0-9_\\.<>]*)", options: [.anchorsMatchLines])),
            (.function, try! NSRegularExpression(pattern: "^[\\t ]*(?:public\\s+|private\\s+|internal\\s+|fileprivate\\s+|open\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [.anchorsMatchLines])),
            (.initializer, try! NSRegularExpression(pattern: "^[\\t ]*init\\s*\\(", options: [.anchorsMatchLines]))
        ]

        return extract(patterns: patterns, content: content)
    }

    private static func parseJSTS(content: String) -> [(name: String, kind: SymbolKind, line: Int)] {
        let patterns: [(SymbolKind, NSRegularExpression)] = [
            (.class, try! NSRegularExpression(pattern: "^[\\t ]*class\\s+([A-Za-z_\\$][A-Za-z0-9_\\$]*)", options: [.anchorsMatchLines])),
            (.function, try! NSRegularExpression(pattern: "^[\\t ]*function\\s+([A-Za-z_\\$][A-Za-z0-9_\\$]*)", options: [.anchorsMatchLines])),
            (.function, try! NSRegularExpression(pattern: "^[\\t ]*export\\s+function\\s+([A-Za-z_\\$][A-Za-z0-9_\\$]*)", options: [.anchorsMatchLines])),
            (.variable, try! NSRegularExpression(pattern: "^[\\t ]*(?:export\\s+)?const\\s+([A-Za-z_\\$][A-Za-z0-9_\\$]*)\\s*=\\s*\\(", options: [.anchorsMatchLines])),
            (.variable, try! NSRegularExpression(pattern: "^[\\t ]*(?:export\\s+)?const\\s+([A-Za-z_\\$][A-Za-z0-9_\\$]*)\\s*=\\s*async\\s*\\(", options: [.anchorsMatchLines]))
        ]

        return extract(patterns: patterns, content: content)
    }

    private static func parsePython(content: String) -> [(name: String, kind: SymbolKind, line: Int)] {
        let patterns: [(SymbolKind, NSRegularExpression)] = [
            (.class, try! NSRegularExpression(pattern: "^[\\t ]*class\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [.anchorsMatchLines])),
            (.function, try! NSRegularExpression(pattern: "^[\\t ]*def\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(", options: [.anchorsMatchLines]))
        ]

        return extract(patterns: patterns, content: content)
    }

    private static func extract(patterns: [(SymbolKind, NSRegularExpression)], content: String) -> [(name: String, kind: SymbolKind, line: Int)] {
        let ns = content as NSString
        var out: [(name: String, kind: SymbolKind, line: Int)] = []

        for (kind, regex) in patterns {
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let name: String
                if kind == .initializer {
                    name = "init"
                } else {
                    guard m.numberOfRanges >= 2 else { continue }
                    name = ns.substring(with: m.range(at: 1))
                }

                let line = lineNumber(for: m.range.location, in: ns)
                out.append((name: name, kind: kind, line: line))
            }
        }

        // Stable sort by line then name
        out.sort { a, b in
            if a.line != b.line { return a.line < b.line }
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            return a.name < b.name
        }

        return out
    }

    private static func lineNumber(for utf16Location: Int, in ns: NSString) -> Int {
        if utf16Location <= 0 { return 1 }

        var line = 1
        var i = 0
        while i < min(utf16Location, ns.length) {
            if ns.character(at: i) == 10 { line += 1 } // '\n'
            i += 1
        }
        return line
    }
}

@MainActor
final class WorkspaceSymbolSearchService {
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?

    init(codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?) {
        self.codebaseIndexProvider = codebaseIndexProvider
    }

    func search(
        query rawQuery: String,
        projectRoot: URL,
        currentFilePath: String?,
        currentContent: String?,
        currentLanguage: String?,
        limit: Int
    ) -> [WorkspaceSymbolLocation] {
        let needle = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if needle.isEmpty {
            guard let currentFilePath, let currentContent, let currentLanguage else { return [] }
            guard let rel = Self.relativePath(projectRoot: projectRoot, absolutePath: currentFilePath) else { return [] }
            let parsed = WorkspaceSymbolParser.parse(language: currentLanguage, content: currentContent)
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
           (UserDefaults.standard.object(forKey: "CodebaseIndexEnabled") as? Bool ?? true),
           let matches = try? index.searchSymbolsWithPaths(nameLike: needle, limit: max(1, min(200, limit))) {
            var out: [WorkspaceSymbolLocation] = []
            out.reserveCapacity(min(limit, matches.count))

            for m in matches {
                guard let filePath = m.filePath else { continue }
                guard let rel = Self.relativePath(projectRoot: projectRoot, absolutePath: filePath) else { continue }

                let symbol = m.symbol
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

        let parsed = WorkspaceSymbolParser.parse(language: currentLanguage, content: currentContent)
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

    private func sort(_ items: [WorkspaceSymbolLocation], query: String) -> [WorkspaceSymbolLocation] {
        let needle = query.lowercased()

        func score(_ name: String) -> Int {
            let n = name.lowercased()
            if n == needle { return 1_000 }
            if n.hasPrefix(needle) { return 700 }
            if n.contains(needle) { return 500 }
            return 0
        }

        return items.sorted { a, b in
            let sa = score(a.name)
            let sb = score(b.name)
            if sa != sb { return sa > sb }
            if a.relativePath != b.relativePath { return a.relativePath < b.relativePath }
            if a.line != b.line { return a.line < b.line }
            return a.name < b.name
        }
    }

    static func relativePath(projectRoot: URL, absolutePath: String) -> String? {
        let root = projectRoot.standardizedFileURL.path
        let abs = URL(fileURLWithPath: absolutePath).standardizedFileURL.path
        guard abs.hasPrefix(root + "/") else { return nil }
        return String(abs.dropFirst(root.count + 1))
    }
}
