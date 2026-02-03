import Foundation

public enum ConversationFoldingService {
    public static func shouldFold(messages: [ChatMessage], thresholds: ConversationFoldingThresholds) -> Bool {
        if messages.count > thresholds.maxMessageCount { return true }

        let totalChars = messages.reduce(0) { partial, msg in
            partial + msg.content.count + (msg.reasoning?.count ?? 0) + (msg.codeContext?.count ?? 0)
        }
        return totalChars > thresholds.maxContentCharacters
    }

    public static func fold(messages: [ChatMessage], projectRoot: URL, thresholds: ConversationFoldingThresholds) async throws -> ConversationFoldResult? {
        guard shouldFold(messages: messages, thresholds: thresholds) else { return nil }
        guard messages.count > thresholds.preserveMostRecentMessages else { return nil }

        let foldCount = max(0, messages.count - thresholds.preserveMostRecentMessages)
        guard foldCount > 0 else { return nil }

        let toFold = Array(messages.prefix(foldCount))
        let createdAt = Date()
        let summary = summarize(messages: toFold, createdAt: createdAt)
        let content = serialize(messages: toFold)

        let store = ConversationFoldStore(projectRoot: projectRoot)
        let entry = try await store.write(summary: summary, content: content)
        return ConversationFoldResult(entry: entry, foldedMessageCount: foldCount)
    }

    private static func summarize(messages: [ChatMessage], createdAt: Date) -> String {
        let start = messages.first?.timestamp ?? createdAt
        let end = messages.last?.timestamp ?? createdAt
        let fmt = ISO8601DateFormatter()

        let userSnippets = messages
            .filter { $0.role == .user }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let assistantSnippets = messages
            .filter { $0.role == .assistant }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let toolSnippets = messages
            .filter { $0.role == .tool }
            .compactMap { msg -> String? in
                guard let toolCallId = msg.toolCallId else { return nil }
                let status = msg.toolStatus?.rawValue ?? "unknown"
                let preview = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if preview.isEmpty { return nil }
                return "- \(msg.toolName ?? "unknown_tool") (\(toolCallId)) [\(status)]"
            }

        let reasoningOutcomeSnippets = messages
            .filter { $0.role == .system }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("ReasoningOutcome:") }

        let timeHeader = "Folded \(messages.count) messages (\(fmt.string(from: start)) → \(fmt.string(from: end)))."
        let userHeader = userSnippets.isEmpty ? "(none)" : userSnippets.prefix(5).joined(separator: " | ")
        let assistantHeader = assistantSnippets.isEmpty ? "(none)" : assistantSnippets.prefix(3).joined(separator: " | ")

        let toolSection = toolSnippets.isEmpty ? "(none)" : toolSnippets.prefix(8).joined(separator: "\n")
        let outcomeSection = reasoningOutcomeSnippets.isEmpty ? "(none)" : reasoningOutcomeSnippets.suffix(3).joined(separator: "\n\n")

        return """
        Context summary (auto-generated):
        \(timeHeader)

        User requests/topics:
        \(userHeader)

        Assistant responses (high level):
        \(assistantHeader)

        Tool activity (collapsed):
        \(toolSection)

        Latest ReasoningOutcome (collapsed):
        \(outcomeSection)
        """
    }

    private static func serialize(messages: [ChatMessage]) -> String {
        let fmt = ISO8601DateFormatter()
        return messages.map { msg in
            var parts: [String] = []
            parts.append("[\(fmt.string(from: msg.timestamp))] \(msg.role.rawValue.uppercased())")
            if !msg.content.isEmpty { parts.append(msg.content) }
            return parts.joined(separator: "\n")
        }.joined(separator: "\n\n---\n\n")
    }
}
