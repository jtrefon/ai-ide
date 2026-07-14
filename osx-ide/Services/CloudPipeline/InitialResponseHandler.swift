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
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse {
        var response = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.requestMessages,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.initial_response,
                conversationId: conversationId
            ))
            .get()

        if try await shouldForceAutonomousExecutionFollowup(
            response: response,
            mode: mode,
            userInput: userInput,
            projectRoot: projectRoot,
            availableTools: availableTools,
            runId: runId,
            conversationId: conversationId
        ) {
            let originalContent = response.content ?? ""
            await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.initial", data: [
                "runId": runId,
                "hasToolCalls": false,
                "contentLength": originalContent.count
            ])
            response = try await sendFocusedExecutionFollowup(
                mode: mode,
                projectRoot: projectRoot,
                conversationId: conversationId,
                availableTools: availableTools,
                runId: runId,
                userInput: userInput
            )

            if mode == .agent,
               response.toolCalls?.isEmpty ?? true,
               !availableTools.isEmpty {
                response = try await sendAutonomousToolFollowup(
                    mode: mode,
                    projectRoot: projectRoot,
                    conversationId: conversationId,
                    availableTools: availableTools,
                    runId: runId,
                    userInput: userInput,
                    existingAssistantContent: response.content ?? originalContent
                )
            }
        }

         if mode == .agent || mode == .coder,
            response.toolCalls?.isEmpty ?? true,
            let content = response.content,
            ChatPromptBuilder.isRequestingUserInputForNextStep(content: content),
            !availableTools.isEmpty {
             let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                 userInput: userInput,
                 conversationId: conversationId,
                 projectRoot: projectRoot,
                 historyMessages: historyCoordinator.requestMessages
             )
             response = try await aiInteractionCoordinator
                 .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                     messages: focusedMessages,
                     tools: availableTools,
                     mode: mode,
                     projectRoot: projectRoot,
                     runId: runId,
                     stage: AIRequestStage.tool_loop,
                     conversationId: conversationId
                 ))
                 .get()
         }

         if mode == .agent || mode == .coder,
            response.toolCalls?.isEmpty ?? true,
            let content = response.content,
            ChatPromptBuilder.isRequestingUserInputForNextStep(content: content),
            availableTools.isEmpty {
             let autonomousMessages = try await ToolLoopUtilities.buildAutonomousNoUserInputMessages(
                 userInput: userInput,
                 conversationId: conversationId,
                 projectRoot: projectRoot,
                 existingAssistantContent: content,
                 toolsAvailable: false,
                 historyMessages: historyCoordinator.requestMessages
             )
             response = try await aiInteractionCoordinator
                 .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                     messages: autonomousMessages,
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

    private func shouldForceAutonomousExecutionFollowup(
        response: AIServiceResponse,
        mode: AIMode,
        userInput: String,
        projectRoot: URL,
        availableTools: [AITool],
        runId: String,
        conversationId: String
    ) async throws -> Bool {
        guard mode.isAgentic,
              response.toolCalls?.isEmpty ?? true,
              !availableTools.isEmpty else {
            return false
        }

        let requestNeedsExecution =
            ChatPromptBuilder.userRequestRequiresExecution(userInput: userInput)
            || ChatPromptBuilder.userRequestRequiresToolBackedInvestigation(userInput: userInput)
        guard requestNeedsExecution else {
            return false
        }

        let content = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty {
            return true
        }

        if ChatPromptBuilder.shouldForceToolFollowup(content: content)
            || ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: userInput,
                content: content,
                hasToolCalls: false
            )
            || ChatPromptBuilder.indicatesWorkWasPerformed(content: content)
            || ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                content: content,
                projectRoot: projectRoot
            ) {
            return true
        }

        if let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: content),
           deliveryStatus == .needsWork {
            return true
        }

        await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.initial.request_requires_execution", data: [
            "runId": runId,
            "conversationId": conversationId,
            "contentLength": content.count
        ])
        return true
    }

    private func sendFocusedExecutionFollowup(
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse {
        let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot,
            historyMessages: historyCoordinator.requestMessages
        )
        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: focusedMessages,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop,
                conversationId: conversationId
            ))
            .get()
    }

    private func sendAutonomousToolFollowup(
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String,
        existingAssistantContent: String
    ) async throws -> AIServiceResponse {
        let autonomousMessages = try await ToolLoopUtilities.buildAutonomousNoUserInputMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot,
            existingAssistantContent: existingAssistantContent,
            toolsAvailable: true,
            historyMessages: historyCoordinator.requestMessages
        )
        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: autonomousMessages,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop,
                conversationId: conversationId
            ))
            .get()
    }
}
