import Foundation

public enum ContextBuilder {
    @MainActor
    public static func buildContext(userInput: String, explicitContext: String?, index: CodebaseIndexProtocol?) -> String? {
        var parts: [String] = []

        if let explicitContext, !explicitContext.isEmpty {
            parts.append(explicitContext)
        }

        guard let index else {
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        // Very lightweight heuristic: use a few meaningful tokens from the user input
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

        if let longTerm = try? index.getMemories(tier: .longTerm), !longTerm.isEmpty {
            let lines = longTerm.prefix(15).map { "- \($0.content)" }
            parts.append("PROJECT MEMORY (long-term rules):\n" + lines.joined(separator: "\n"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
