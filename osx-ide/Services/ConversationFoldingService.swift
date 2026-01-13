import Foundation

public struct ConversationFoldingThresholds: Sendable {
    public let maxMessageCount: Int
    public let maxContentCharacters: Int
    public let preserveMostRecentMessages: Int

    public init(maxMessageCount: Int = 40, maxContentCharacters: Int = 20_000, preserveMostRecentMessages: Int = 20) {
        self.maxMessageCount = maxMessageCount
        self.maxContentCharacters = maxContentCharacters
        self.preserveMostRecentMessages = preserveMostRecentMessages
    }
}

public struct ConversationFoldResult: Sendable {
    public let entry: ConversationFoldIndexEntry
    public let foldedMessageCount: Int

    public init(entry: ConversationFoldIndexEntry, foldedMessageCount: Int) {
        self.entry = entry
        self.foldedMessageCount = foldedMessageCount
    }
}

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

        let joined = userSnippets.prefix(3).joined(separator: " | ")
        if joined.isEmpty {
            return "Folded \(messages.count) messages (\(fmt.string(from: start)) → \(fmt.string(from: end)))."
        }
        return "Folded \(messages.count) messages (\(fmt.string(from: start)) → \(fmt.string(from: end))). " +
                "User topics: \(joined)"
    }

    private static func serialize(messages: [ChatMessage]) -> String {
        let fmt = ISO8601DateFormatter()
        return messages.map { msg in
            var parts: [String] = []
            parts.append("[\(fmt.string(from: msg.timestamp))] \(msg.role.rawValue.uppercased())")
            if !msg.content.isEmpty { parts.append(msg.content) }
            if let reasoning = msg.reasoning, !reasoning.isEmpty { parts.append("REASONING:\n\(reasoning)") }
            if let codeContext = msg.codeContext, !codeContext.isEmpty { parts.append("CODE_CONTEXT:\n\(codeContext)") }
            return parts.joined(separator: "\n")
        }.joined(separator: "\n\n---\n\n")
    }
}
