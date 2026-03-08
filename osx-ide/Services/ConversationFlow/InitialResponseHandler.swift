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
        conversationId: String,
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
                stage: AIRequestStage.initial_response,
                conversationId: conversationId
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
                || ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                    content: content,
                    projectRoot: projectRoot
                )
           ),
           !availableTools.isEmpty {
             await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.initial", data: [
                 "runId": runId,
                 "hasToolCalls": false,
                 "contentLength": content.count
             ])
             let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                 userInput: userInput,
                 conversationId: conversationId,
                 projectRoot: projectRoot
             )
             response = try await aiInteractionCoordinator
                 .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                     messages: focusedMessages,
                     explicitContext: explicitContext,
                     tools: availableTools,
                     mode: mode,
                     projectRoot: projectRoot,
                     runId: runId,
                     stage: AIRequestStage.tool_loop,
                     conversationId: conversationId
                 ))
                 .get()
         }

         if mode == .agent,
            response.toolCalls?.isEmpty ?? true,
            let content = response.content,
            ChatPromptBuilder.isRequestingUserInputForNextStep(content: content),
            !availableTools.isEmpty {
             let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                 userInput: userInput,
                 conversationId: conversationId,
                 projectRoot: projectRoot
             )
             response = try await aiInteractionCoordinator
                 .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                     messages: focusedMessages,
                     explicitContext: explicitContext,
                     tools: availableTools,
                     mode: mode,
                     projectRoot: projectRoot,
                     runId: runId,
                     stage: AIRequestStage.tool_loop,
                     conversationId: conversationId
                 ))
                 .get()
         }

         if mode == .agent,
            response.toolCalls?.isEmpty ?? true,
            let content = response.content,
            ChatPromptBuilder.isRequestingUserInputForNextStep(content: content),
            availableTools.isEmpty {
             let autonomousMessages = try await ToolLoopUtilities.buildAutonomousNoUserInputMessages(
                 userInput: userInput,
                 conversationId: conversationId,
                 projectRoot: projectRoot,
                 existingAssistantContent: content,
                 toolsAvailable: false
             )
             response = try await aiInteractionCoordinator
                 .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                     messages: autonomousMessages,
                     explicitContext: explicitContext,
                     tools: availableTools,
                     mode: mode,
                     projectRoot: projectRoot,
                     runId: runId,
                     stage: AIRequestStage.initial_response,
                     conversationId: conversationId
                 ))
                 .get()
         }

        return response
    }
}
