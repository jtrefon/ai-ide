import Foundation
import Combine
import SQLite3

public enum ContextBuilder {
    public static func buildContext(userInput: String, explicitContext: String?, index: CodebaseIndexProtocol?, projectRoot: URL?) async -> String? {
        var parts: [String] = []

        func relPath(_ absPath: String) -> String {
            guard let projectRoot else { return absPath }
            let root = projectRoot.standardizedFileURL.path
            if absPath.hasPrefix(root + "/") {
                return String(absPath.dropFirst(root.count + 1))
            }
            return absPath
        }

        if let explicitContext, !explicitContext.isEmpty {
            parts.append(explicitContext)
        }

        guard let index else {
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        // 1. High-level Project Summaries (if available)
        if let root = projectRoot,
           let summaries = try? await index.getSummaries(projectRoot: root, limit: 10),
           !summaries.isEmpty {
            let summaryLines = summaries.map { "- \(relPath($0.path)): \($0.summary)" }
            parts.append("PROJECT OVERVIEW (Key Files):\n" + summaryLines.joined(separator: "\n"))
        }

        // 2. Symbols from lightweight heuristic
        let tokens = userInput
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map { String($0) }
            .filter { $0.count >= 3 }

        let uniqueTokens = Array(Set(tokens)).prefix(5)

        var symbolResults: [SymbolSearchResult] = []
        for token in uniqueTokens {
            if let found = try? await index.searchSymbolsWithPaths(nameLike: token, limit: 10) {
                symbolResults.append(contentsOf: found)
            }
        }

        if !symbolResults.isEmpty {
            let lines = symbolResults.prefix(25).map { result in
                let symbol = result.symbol
                if let filePath = result.filePath {
                    return "- [\(symbol.kind.rawValue)] \(symbol.name) (\(relPath(filePath)):\(symbol.lineStart)-\(symbol.lineEnd))"
                }
                return "- [\(symbol.kind.rawValue)] \(symbol.name) (lines \(symbol.lineStart)-\(symbol.lineEnd))"
            }
            parts.append("CODEBASE INDEX (matching symbols):\n" + lines.joined(separator: "\n"))
        }

        // 3. Project Memory
        if let longTerm = try? await index.getMemories(tier: .longTerm), !longTerm.isEmpty {
            let lines = longTerm.prefix(15).map { "- \($0.content)" }
            parts.append("PROJECT MEMORY (long-term rules):\n" + lines.joined(separator: "\n"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
