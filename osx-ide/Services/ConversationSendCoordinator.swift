import Foundation

@MainActor
final class ConversationSendCoordinator {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let toolExecutionCoordinator: ToolExecutionCoordinator

    private let foldingHandler: ConversationFoldingHandler
    private let initialResponseHandler: InitialResponseHandler
    private let toolLoopHandler: ToolLoopHandler
    private let qaReviewHandler: QAReviewHandler
    private let reasoningCorrectionsHandler: ReasoningCorrectionsHandler
    private let finalResponseHandler: FinalResponseHandler

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        toolExecutionCoordinator: ToolExecutionCoordinator
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
        self.toolExecutionCoordinator = toolExecutionCoordinator

        self.foldingHandler = ConversationFoldingHandler()
        self.initialResponseHandler = InitialResponseHandler(
            aiInteractionCoordinator: aiInteractionCoordinator,
            historyCoordinator: historyCoordinator
        )
        self.toolLoopHandler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )
        self.qaReviewHandler = QAReviewHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator
        )
        self.reasoningCorrectionsHandler = ReasoningCorrectionsHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator
        )
        self.finalResponseHandler = FinalResponseHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator
        )
    }

    func send(
        _ request: SendRequest
    ) async throws {
        try await foldingHandler.foldIfNeeded(
            historyCoordinator: historyCoordinator,
            projectRoot: request.projectRoot
        )
        let response = try await executeConversationFlow(request)
        finalResponseHandler.appendFinalMessageAndLog(response: response, conversationId: request.conversationId)
    }

    private func executeConversationFlow(_ request: SendRequest) async throws -> AIServiceResponse {
        let initialResponse = try await initialResponseHandler.sendInitialResponse(
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId
        )

        await appendRunSnapshot(payload: RunSnapshotPayload(
            runId: request.runId,
            conversationId: request.conversationId,
            phase: "initial_response",
            iteration: nil,
            userInput: request.userInput,
            assistantDraft: initialResponse.content,
            failureReason: nil,
            toolCalls: initialResponse.toolCalls ?? [],
            toolResults: []
        ))

        let toolLoopResult = try await toolLoopHandler.handleToolLoopIfNeeded(
            response: initialResponse,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            conversationId: request.conversationId,
            availableTools: request.availableTools,
            cancelledToolCallIds: request.cancelledToolCallIds,
            runId: request.runId,
            userInput: request.userInput
        )

        var response = toolLoopResult.response
        var lastToolResults = toolLoopResult.lastToolResults

        response = try await reasoningCorrectionsHandler.applyReasoningCorrectionsIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId
        )

        if request.mode == .agent, response.toolCalls?.isEmpty == false {
            let followupToolLoopResult = try await toolLoopHandler.handleToolLoopIfNeeded(
                response: response,
                explicitContext: request.explicitContext,
                mode: request.mode,
                projectRoot: request.projectRoot,
                conversationId: request.conversationId,
                availableTools: request.availableTools,
                cancelledToolCallIds: request.cancelledToolCallIds,
                runId: request.runId,
                userInput: request.userInput
            )
            response = followupToolLoopResult.response
            lastToolResults = followupToolLoopResult.lastToolResults
        }

        response = try await reasoningCorrectionsHandler.enforceDeliveryCompletionIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        if request.mode == .agent, response.toolCalls?.isEmpty == false {
            let followupToolLoopResult = try await toolLoopHandler.handleToolLoopIfNeeded(
                response: response,
                explicitContext: request.explicitContext,
                mode: request.mode,
                projectRoot: request.projectRoot,
                conversationId: request.conversationId,
                availableTools: request.availableTools,
                cancelledToolCallIds: request.cancelledToolCallIds,
                runId: request.runId,
                userInput: request.userInput
            )
            response = followupToolLoopResult.response
            lastToolResults = followupToolLoopResult.lastToolResults
        }

        if request.mode == .agent {
            let trimmed = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasToolCalls = (response.toolCalls?.isEmpty == false)
            if trimmed.isEmpty, !hasToolCalls {
                let promptText = PromptRepository.shared.prompt(
                    key: "ConversationFlow/Corrections/empty_response_followup",
                    defaultValue: "In Agent mode you returned an empty response. You must continue autonomously. " +
                        "If tools are needed, return tool calls now. If you are done, provide the final answer. " +
                        "Do not ask the user for more inputs as the next step.",
                    projectRoot: request.projectRoot
                )
                let followupSystem = ChatMessage(
                    role: .system,
                    content: promptText
                )
                let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user })

                var followupMessages = historyCoordinator.messages
                followupMessages.append(followupSystem)
                if let lastUserMessage {
                    followupMessages.append(lastUserMessage)
                }

                response = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: followupMessages,
                        explicitContext: request.explicitContext,
                        tools: request.availableTools,
                        mode: request.mode,
                        projectRoot: request.projectRoot,
                        runId: request.runId,
                        stage: AIRequestStage.delivery_gate
                    ))
                    .get()

                if response.toolCalls?.isEmpty == false {
                    let followupToolLoopResult = try await toolLoopHandler.handleToolLoopIfNeeded(
                        response: response,
                        explicitContext: request.explicitContext,
                        mode: request.mode,
                        projectRoot: request.projectRoot,
                        conversationId: request.conversationId,
                        availableTools: request.availableTools,
                        cancelledToolCallIds: request.cancelledToolCallIds,
                        runId: request.runId,
                        userInput: request.userInput
                    )
                    response = followupToolLoopResult.response
                    lastToolResults = followupToolLoopResult.lastToolResults
                }
            }
        }

        response = try await finalResponseHandler.requestFinalResponseIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            toolResults: lastToolResults,
            runId: request.runId
        )

        response = try await qaReviewHandler.performToolOutputReviewIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            qaReviewEnabled: request.qaReviewEnabled,
            availableTools: request.availableTools,
            toolResults: lastToolResults,
            runId: request.runId,
            userInput: request.userInput
        )

        response = try await qaReviewHandler.performQualityReviewIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            qaReviewEnabled: request.qaReviewEnabled,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        response = try await reasoningCorrectionsHandler.enforceDeliveryCompletionIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        if request.mode == .agent, response.toolCalls?.isEmpty == false {
            let followupToolLoopResult = try await toolLoopHandler.handleToolLoopIfNeeded(
                response: response,
                explicitContext: request.explicitContext,
                mode: request.mode,
                projectRoot: request.projectRoot,
                conversationId: request.conversationId,
                availableTools: request.availableTools,
                cancelledToolCallIds: request.cancelledToolCallIds,
                runId: request.runId,
                userInput: request.userInput
            )
            response = followupToolLoopResult.response
            lastToolResults = followupToolLoopResult.lastToolResults
        }

        return response
    }

    private func appendRunSnapshot(payload: RunSnapshotPayload) async {
        let snapshot = OrchestrationRunSnapshot(
            runId: payload.runId,
            conversationId: payload.conversationId,
            phase: payload.phase,
            iteration: payload.iteration,
            timestamp: Date(),
            userInput: payload.userInput,
            assistantDraft: payload.assistantDraft,
            failureReason: payload.failureReason,
            toolCalls: toolCallSummaries(payload.toolCalls),
            toolResults: toolResultSummaries(payload.toolResults)
        )
        try? await OrchestrationRunStore.shared.appendSnapshot(snapshot)
    }

    private func toolCallSummaries(_ toolCalls: [AIToolCall]) -> [OrchestrationRunSnapshot.ToolCallSummary] {
        toolCalls.map {
            OrchestrationRunSnapshot.ToolCallSummary(
                id: $0.id,
                name: $0.name,
                argumentKeys: Array($0.arguments.keys).sorted()
            )
        }
    }

    private func toolResultSummaries(_ toolResults: [ChatMessage]) -> [OrchestrationRunSnapshot.ToolResultSummary] {
        toolResults.compactMap { message in
            guard let toolCallId = message.toolCallId else { return nil }
            let output = toolOutputText(from: message)
            return OrchestrationRunSnapshot.ToolResultSummary(
                toolCallId: toolCallId,
                toolName: message.toolName ?? "unknown_tool",
                status: message.toolStatus?.rawValue ?? "unknown",
                targetFile: message.targetFile,
                outputPreview: truncate(output, limit: 1200)
            )
        }
    }

    private func toolOutputText(from message: ChatMessage) -> String {
        guard message.isToolExecution else { return message.content }
        if let envelope = ToolExecutionEnvelope.decode(from: message.content) {
            if let payload = envelope.payload?.trimmingCharacters(in: .whitespacesAndNewlines),
               !payload.isEmpty {
                return payload
            }
            return envelope.message
        }
        return message.content
    }

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }
}
