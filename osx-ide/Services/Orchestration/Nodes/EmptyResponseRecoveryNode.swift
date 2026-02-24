import Foundation

@MainActor
struct EmptyResponseRecoveryNode: OrchestrationNode {
    let id: String

    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let toolLoopHandler: ToolLoopHandler
    private let nextNodeId: String

    init(
        id: String,
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        toolLoopHandler: ToolLoopHandler,
        nextNodeId: String
    ) {
        self.id = id
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
        self.toolLoopHandler = toolLoopHandler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        guard request.mode == .agent else {
            return OrchestrationState(
                request: request,
                response: response,
                lastToolResults: state.lastToolResults,
                transition: .next(nextNodeId)
            )
        }

        let trimmed = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasToolCalls = (response.toolCalls?.isEmpty == false)
        guard trimmed.isEmpty, !hasToolCalls else {
            return OrchestrationState(
                request: request,
                response: response,
                lastToolResults: state.lastToolResults,
                transition: .next(nextNodeId)
            )
        }

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

        var recovered = try await aiInteractionCoordinator
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

        var lastToolResults = state.lastToolResults

        if recovered.toolCalls?.isEmpty == false {
            let followupToolLoopResult = try await toolLoopHandler.handleToolLoopIfNeeded(
                response: recovered,
                explicitContext: request.explicitContext,
                mode: request.mode,
                projectRoot: request.projectRoot,
                conversationId: request.conversationId,
                availableTools: request.availableTools,
                cancelledToolCallIds: request.cancelledToolCallIds,
                runId: request.runId,
                userInput: request.userInput
            )
            recovered = followupToolLoopResult.response
            lastToolResults = followupToolLoopResult.lastToolResults
        }

        let retriedContent = recovered.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let retriedHasToolCalls = (recovered.toolCalls?.isEmpty == false)
        if retriedContent.isEmpty, !retriedHasToolCalls {
            recovered = AIServiceResponse(
                content: "I wasn't able to generate a final response. Please retry or clarify the next step.",
                toolCalls: nil
            )
        }

        return OrchestrationState(
            request: request,
            response: recovered,
            lastToolResults: lastToolResults,
            transition: .next(nextNodeId)
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("EmptyResponseRecoveryNode(\(id)): expected response to be set")
        }
        return response
    }
}
