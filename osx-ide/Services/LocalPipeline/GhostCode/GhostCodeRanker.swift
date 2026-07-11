import Foundation

enum GhostCodeRankerEvaluation {
    case accepted(InlineSuggestionPresentation)
    case rejected(String)
}

@MainActor
struct GhostCodeRanker {
    func evaluate(_ result: InlineCompletionResult, for request: InlineCompletionRequest, aggressiveness: Double) -> GhostCodeRankerEvaluation {
        guard let sanitized = sanitizedSuggestion(from: result.suggestionText) else {
            return .rejected("sanitized_nil")
        }
        guard !sanitized.isEmpty else { return .rejected("empty") }
        guard !hasSelfRepetition(sanitized) else { return .rejected("self_repetition") }
        guard respectsIndentation(sanitized, prefix: request.prefix) else { return .rejected("indentation") }
        guard sanitized.count <= request.maxSuggestionLength else { return .rejected("too_long") }

        let score = min(0.98, max(aggressiveness, result.confidenceScore))
        return .accepted(InlineSuggestionPresentation(
            requestId: result.requestId,
            suggestionText: sanitized,
            source: result.source,
            confidenceScore: score,
            latencyMs: result.latencyMs
        ))
    }

    func rank(_ result: InlineCompletionResult, for request: InlineCompletionRequest, aggressiveness: Double) -> InlineSuggestionPresentation? {
        switch evaluate(result, for: request, aggressiveness: aggressiveness) {
        case .accepted(let p): return p
        case .rejected: return nil
        }
    }

    private func sanitizedSuggestion(from raw: String) -> String? {
        let normalizedRaw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var text = normalizedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCodeFenceWrapped = text.hasPrefix("```")
        if isCodeFenceWrapped {
            text = text.replacingOccurrences(of: #"^```[A-Za-z0-9_-]*\n?"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }

    private func hasSelfRepetition(_ suggestion: String) -> Bool {
        let words = suggestion.split(separator: " ").filter { !$0.isEmpty }
        guard words.count >= 6 else { return false }
        for n in 2...3 {
            if words.count >= n * 2 {
                let first = words[0..<n]
                let second = words[n..<(n*2)]
                if first == second { return true }
            }
        }
        return false
    }

    private func respectsIndentation(_ suggestion: String, prefix: String) -> Bool {
        guard suggestion.contains("\n") else { return true }
        guard let lastLine = prefix.components(separatedBy: .newlines).last else { return true }
        let indentation = lastLine.prefix { $0 == " " || $0 == "\t" }
        let lines = suggestion.components(separatedBy: .newlines).dropFirst()
        return lines.allSatisfy { line in
            line.isEmpty || line.hasPrefix(String(indentation))
        }
    }
}
