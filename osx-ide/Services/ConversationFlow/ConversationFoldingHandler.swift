import Foundation

@MainActor
final class ConversationFoldingHandler {
    func foldIfNeeded(
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL
    ) async throws {
        let provider = AIProviderSettingsStore().load()
        let tokenBudget: Int?
        if provider == .local {
            tokenBudget = LocalModelSettingsStore().load().contextBudgetTokens
        } else {
            tokenBudget = nil
        }

        let foldResult: ConversationFoldResult?
        if let tokenBudget {
            foldResult = try await ConversationFoldingService.foldIfOverTokenBudget(
                messages: historyCoordinator.messages,
                projectRoot: projectRoot,
                tokenBudget: tokenBudget,
                triggerRatio: 0.7,
                preserveMostRecentMessages: 20
            )
        } else {
            foldResult = nil
        }

        let thresholds = ConversationFoldingThresholds()
        let resolvedFoldResult: ConversationFoldResult?
        if let foldResult {
            resolvedFoldResult = foldResult
        } else {
            resolvedFoldResult = try await ConversationFoldingService.fold(
                messages: historyCoordinator.messages,
                projectRoot: projectRoot,
                thresholds: thresholds
            )
        }

        if let foldResult = resolvedFoldResult {
            let summaryMessage = ChatMessage(
                role: .system,
                content: foldResult.entry.summary
            )
            historyCoordinator.replaceOldestMessages(count: foldResult.foldedMessageCount, with: summaryMessage)
            await AIToolTraceLogger.shared.log(type: "chat.context_folded", data: [
                "foldId": foldResult.entry.id,
                "foldedMessageCount": foldResult.foldedMessageCount,
                "summary": foldResult.entry.summary
            ])
        }
    }
}
