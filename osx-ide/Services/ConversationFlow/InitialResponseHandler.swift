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
        runId: String,
        userInput: String
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
           (
                ChatPromptBuilder.shouldForceToolFollowup(content: content)
                || ChatPromptBuilder.shouldForceExecutionFollowup(
                    userInput: userInput,
                    content: content,
                    hasToolCalls: false
                )
           ),
           let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user }) {
            await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.initial", data: [
                "runId": runId,
                "hasToolCalls": false,
                "contentLength": content.count
            ])
            let promptText = try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/force_tool_followup",
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
            let promptText = try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/no_user_input_next_step",
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

        // Retry if response contains only reasoning without actual content
        if mode == .agent,
           response.toolCalls?.isEmpty ?? true,
           let content = response.content,
           ChatPromptBuilder.isReasoningOnly(content: content),
           let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user }) {
            await AIToolTraceLogger.shared.log(type: "chat.force_retry.reasoning_only.initial", data: [
                "runId": runId,
                "hasToolCalls": false,
                "contentLength": content.count
            ])
            let promptText = try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/reasoning_only_retry",
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

        return response
    }
}
