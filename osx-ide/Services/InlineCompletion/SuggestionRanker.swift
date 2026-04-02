import Foundation

enum SuggestionRankerEvaluation {
    case accepted(InlineSuggestionPresentation)
    case rejected(String)
}

@MainActor
struct SuggestionRanker {
    func rank(
        _ result: InlineCompletionResult,
        for request: InlineCompletionRequest,
        aggressiveness: Double
    ) -> InlineSuggestionPresentation? {
        switch evaluate(result, for: request, aggressiveness: aggressiveness) {
        case let .accepted(presentation):
            return presentation
        case .rejected:
            return nil
        }
    }

    func evaluate(
        _ result: InlineCompletionResult,
        for request: InlineCompletionRequest,
        aggressiveness: Double
    ) -> SuggestionRankerEvaluation {
        guard let sanitized = sanitizedSuggestion(from: result.suggestionText, allowMultiline: request.allowMultiline) else {
            return .rejected("sanitized_nil")
        }

        guard !sanitized.isEmpty else { return .rejected("empty") }
        guard !request.suffix.hasPrefix(sanitized) else { return .rejected("suffix_prefix_duplicate") }
        guard !duplicatesLeadingSuffix(sanitized, suffix: request.suffix) else { return .rejected("leading_suffix_duplicate") }
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

    private func sanitizedSuggestion(from raw: String, allowMultiline: Bool) -> String? {
        let normalizedRaw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var text = normalizedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCodeFenceWrapped = text.hasPrefix("```")

        if isCodeFenceWrapped {
            text = text.replacingOccurrences(of: #"^```[A-Za-z0-9_-]*\n?"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !allowMultiline {
            if !isCodeFenceWrapped, normalizedRaw.contains("\n") { return nil }
            if text.contains("\n") { return nil }
        }

        if text.lowercased().hasPrefix("here") || text.lowercased().hasPrefix("the ") {
            return nil
        }

        return text
    }

    private func duplicatesLeadingSuffix(_ suggestion: String, suffix: String) -> Bool {
        let candidate = suggestion.trimmingCharacters(in: .whitespaces)
        let remaining = suffix.trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty, !remaining.isEmpty else { return false }
        return remaining.hasPrefix(candidate)
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
