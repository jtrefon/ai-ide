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
        availableTools: [AITool],
        runId: String
    ) async throws -> AIServiceResponse {
        var response = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages,
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.initial_response
            ))
            .get()

        if mode == .agent,
           response.toolCalls?.isEmpty ?? true,
           let content = response.content,
           ChatPromptBuilder.shouldForceToolFollowup(content: content),
           let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user }) {
            let promptText = PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/force_tool_followup",
                defaultValue: "You indicated you will implement changes, but you returned no tool calls. " +
                    "In Agent mode, you MUST now proceed by calling the appropriate tools. " +
                    "Return tool calls now.",
                projectRoot: projectRoot
            )
            let followupSystem = ChatMessage(
                role: .system,
                content: promptText
            )

            response = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [followupSystem, lastUserMessage],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.initial_response
                ))
                .get()
        }

        if mode == .agent,
           response.toolCalls?.isEmpty ?? true,
           let content = response.content,
           ChatPromptBuilder.isRequestingUserInputForNextStep(content: content) {
            let promptText = PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/no_user_input_next_step",
                defaultValue: "In Agent mode, do not ask the user for additional inputs (diffs, files, confirmations) as a next step. " +
                    "Proceed autonomously using the available tools and make reasonable assumptions. " +
                    "If multiple options exist, pick the safest default and continue. Return tool calls now if needed.",
                projectRoot: projectRoot
            )
            let followupSystem = ChatMessage(
                role: .system,
                content: promptText
            )

            response = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [followupSystem],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.initial_response
                ))
                .get()
        }

        return response
    }
}
