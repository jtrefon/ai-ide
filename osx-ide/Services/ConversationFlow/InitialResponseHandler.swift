import Foundation

@MainActor
final class InitialResponseHandler {
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let historyCoordinator: ChatHistoryCoordinator

    init(
        aiInteractionCoordinator: AIInteractionCoordinator,
        historyCoordinator: ChatHistoryCoordinator
    ) {
        self.aiInteractionCoordinator = aiInteractionCoordinator
        self.historyCoordinator = historyCoordinator
    }

    func sendInitialResponse(
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        availableTools: [AITool]
    ) async throws -> AIServiceResponse {
        var response = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages,
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot
            ))
            .get()

        if mode == .agent,
           response.toolCalls?.isEmpty ?? true,
           let content = response.content,
           ChatPromptBuilder.shouldForceToolFollowup(content: content),
           let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user }) {
            let followupSystem = ChatMessage(
                role: .system,
                content: "You indicated you will implement changes, but you returned no tool calls. " +
                    "In Agent mode, you MUST now proceed by calling the appropriate tools. " +
                    "Return tool calls now."
            )

            response = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [followupSystem, lastUserMessage],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                ))
                .get()
        }

        return response
    }
}
