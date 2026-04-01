import Foundation

@MainActor
struct SuggestionRanker {
    func rank(
        _ result: InlineCompletionResult,
        for request: InlineCompletionRequest,
        aggressiveness: Double
    ) -> InlineSuggestionPresentation? {
        guard let sanitized = sanitizedSuggestion(from: result.suggestionText, allowMultiline: request.allowMultiline) else {
            return nil
        }

        guard !sanitized.isEmpty else { return nil }
        guard !request.suffix.hasPrefix(sanitized) else { return nil }
        guard !duplicatesLeadingSuffix(sanitized, suffix: request.suffix) else { return nil }
        guard respectsIndentation(sanitized, prefix: request.prefix) else { return nil }
        guard sanitized.count <= request.maxSuggestionLength else { return nil }

        let score = min(0.98, max(aggressiveness, result.confidenceScore))
        return InlineSuggestionPresentation(
            requestId: result.requestId,
            suggestionText: sanitized,
            source: result.source,
            confidenceScore: score,
            latencyMs: result.latencyMs
        )
    }

    private func sanitizedSuggestion(from raw: String, allowMultiline: Bool) -> String? {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```[A-Za-z0-9_-]*\n?"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !allowMultiline, let firstLine = text.components(separatedBy: .newlines).first {
            text = firstLine
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

