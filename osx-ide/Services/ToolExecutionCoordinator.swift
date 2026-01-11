import Foundation

@MainActor
final class ToolExecutionCoordinator {
    private let toolExecutor: AIToolExecutor

    init(toolExecutor: AIToolExecutor) {
        self.toolExecutor = toolExecutor
    }

    func executeToolCalls(
        _ toolCalls: [AIToolCall],
        availableTools: [AITool],
        conversationId: String,
        onProgressMessage: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) async -> [ChatMessage] {
        await toolExecutor.executeBatch(
            toolCalls,
            availableTools: availableTools,
            conversationId: conversationId,
            onProgress: onProgressMessage
        )
    }
}
