import Foundation

@MainActor
final class ConversationFoldingHandler {
    func foldIfNeeded(
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL,
        mode: AIMode = .chat
    ) async throws {
        let thresholds: ConversationFoldingThresholds = (mode == .agent) ? .agent : .chat
        let messages = historyCoordinator.messages
        guard ConversationFoldingService.shouldFold(messages: messages, thresholds: thresholds) else { return }

        // Build living MISSION from all user messages — this is the north star
        // that survives folding so the agent never loses sight of user intent.
        let allUserMessages = messages.filter { $0.role == .user }
        let missionContent = buildMissionStatement(from: allUserMessages, existingMission: findExistingMission(in: messages))
        let missionMessage = ChatMessage(role: .system, content: missionContent)

        // Preserve: system prompt (persona) + MISSION (user intent)
        // Only fold: agent's action history (tool calls, tool results, intermediate responses)
        var preserved: [ChatMessage] = []
        var foldable: [ChatMessage] = []

        for msg in messages {
            if msg.role == .user { continue }  // user messages distilled into MISSION
            if msg.role == .system && msg.content.hasPrefix("MISSION") { continue }  // old MISSION replaced
            if msg.role == .system && !msg.content.hasPrefix("MISSION") {
                preserved.append(msg)  // keep persona/system prompt
            } else {
                foldable.append(msg)
            }
        }
        preserved.append(missionMessage)

        guard ConversationFoldingService.shouldFold(messages: foldable, thresholds: thresholds) else { return }

        if let foldResult = try await ConversationFoldingService.fold(
            messages: foldable,
            projectRoot: projectRoot,
            thresholds: thresholds
        ) {
            let summaryMessage = ChatMessage(
                role: .system,
                content: foldResult.entry.summary
            )
            let newMessages = preserved + [summaryMessage] + Array(foldable.dropFirst(foldResult.foldedMessageCount))
            historyCoordinator.replaceAllMessages(with: newMessages)
            await AIToolTraceLogger.shared.log(type: "chat.context_folded", data: [
                "foldId": foldResult.entry.id,
                "foldedMessageCount": foldResult.foldedMessageCount,
                "preservedMissionCount": allUserMessages.count,
                "summary": foldResult.entry.summary
            ])
        }
    }

    /// Builds a distilled MISSION statement from all user messages.
    /// Filters out low-signal messages ("ok", "proceed", etc.) and concatenates
    /// the rest into a single flowing goal statement that evolves with user intent.
    private func buildMissionStatement(from userMessages: [ChatMessage], existingMission: String?) -> String {
        let lowSignalPatterns = [
            "please proceed", "go ahead", "continue", "ok", "okay",
            "thanks", "thank you", "yes", "yeah", "sure", "proceed",
            "do it", "go for it", "let's go", "cool", "nice"
        ]

        // Collect meaningful user intents
        var intents: [String] = []

        // Start with existing mission if present
        if let existing = existingMission {
            let prefix = "MISSION:"
            if existing.hasPrefix(prefix) {
                let body = String(existing.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { intents.append(body) }
            }
        }

        for msg in userMessages {
            let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Skip low-signal messages
            let lower = trimmed.lowercased()
            if lowSignalPatterns.contains(where: { lower == $0 || lower.hasPrefix($0) }) {
                continue
            }

            // Skip if already represented
            if intents.contains(where: { $0.localizedCaseInsensitiveContains(trimmed.prefix(30)) }) {
                continue
            }
            if existingMission?.localizedCaseInsensitiveContains(trimmed.prefix(30)) == true {
                continue
            }

            intents.append(trimmed)
        }

        guard !intents.isEmpty else { return "MISSION: Assist the user with their software engineering task." }
        return "MISSION: \(intents.joined(separator: ". "))"
    }

    /// Finds an existing MISSION system message in the conversation.
    private func findExistingMission(in messages: [ChatMessage]) -> String? {
        messages.first(where: { $0.role == .system && $0.content.hasPrefix("MISSION") })?.content
    }
}
