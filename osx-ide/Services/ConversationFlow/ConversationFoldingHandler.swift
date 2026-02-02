import Foundation

@MainActor
final class ConversationFoldingHandler {
    func foldIfNeeded(
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL
    ) async throws {
        let thresholds = ConversationFoldingThresholds()
        if let foldResult = try await ConversationFoldingService.fold(
            messages: historyCoordinator.messages,
            projectRoot: projectRoot,
            thresholds: thresholds
        ) {
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
