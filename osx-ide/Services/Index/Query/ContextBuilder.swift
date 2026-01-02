import Foundation
import Combine
import SQLite3

public enum ContextBuilder {
    @MainActor
    public static func buildContext(userInput: String, explicitContext: String?, index: CodebaseIndexProtocol?, projectRoot: URL?) -> String? {
        var parts: [String] = []

        if let explicitContext, !explicitContext.isEmpty {
            parts.append(explicitContext)
        }

        guard let index else {
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        // 1. High-level Project Summaries (if available)
        if let root = projectRoot,
           let summaries = try? (index as? CodebaseIndex)?.getSummaries(projectRoot: root, limit: 10),
           !summaries.isEmpty {
            let summaryLines = summaries.map { "- \($0.path): \($0.summary)" }
            parts.append("PROJECT OVERVIEW (Key Files):\n" + summaryLines.joined(separator: "\n"))
        }

        // 2. Symbols from lightweight heuristic
        let tokens = userInput
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map { String($0) }
            .filter { $0.count >= 3 }

        let uniqueTokens = Array(Set(tokens)).prefix(5)

        var symbolResults: [Symbol] = []
        for token in uniqueTokens {
            if let found = try? index.searchSymbols(nameLike: token, limit: 10) {
                symbolResults.append(contentsOf: found)
            }
        }

        if !symbolResults.isEmpty {
            let lines = symbolResults.prefix(25).map { symbol in
                "- [\(symbol.kind.rawValue)] \(symbol.name) (resourceId: \(symbol.resourceId), lines \(symbol.lineStart)-\(symbol.lineEnd))"
            }
            parts.append("CODEBASE INDEX (matching symbols):\n" + lines.joined(separator: "\n"))
        }

        // 3. Project Memory
        if let longTerm = try? index.getMemories(tier: .longTerm), !longTerm.isEmpty {
            let lines = longTerm.prefix(15).map { "- \($0.content)" }
            parts.append("PROJECT MEMORY (long-term rules):\n" + lines.joined(separator: "\n"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
