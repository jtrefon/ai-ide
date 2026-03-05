import Foundation

@MainActor
final class ReasoningCorrectionsHandler {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
    }

    func applyReasoningCorrectionsIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        availableTools: [AITool],
        runId: String
    ) async throws -> AIServiceResponse {
        // We no longer perform sequential LLM retry calls here to avoid "Chain Chaos".
        // Instead, we just perform basic validation. If something is critically missing,
        // we can log it or append a system message for the NEXT turn.

        if ChatPromptBuilder.needsReasoningFormatCorrection(text: response.content ?? "") {
            let promptText =
                "Note: If you include reasoning, wrap it in <ide_reasoning>...</ide_reasoning>, keep it compact, and include Reflection/Planning/Continuity sections."
            historyCoordinator.append(ChatMessage(role: .system, content: promptText))
        }

        return response
    }

    func enforceDeliveryCompletionIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        availableTools: [AITool],
        runId: String,
        userInput: String,
        conversationId: String
    ) async throws -> AIServiceResponse {
        guard mode == .agent else { return response }

        let content = response.content ?? ""
        let status = ChatPromptBuilder.deliveryStatus(from: content)
        let hasToolCalls = !(response.toolCalls?.isEmpty ?? true)
        let requiresExecution = ChatPromptBuilder.userRequestRequiresExecution(userInput: userInput)
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        let planIsIncomplete = planProgress.total > 0 && !planProgress.isComplete

        if status == .needsWork, !hasToolCalls, (requiresExecution || planIsIncomplete) {
            let deliveryPrompt = try PromptRepository.shared.prompt(
                key: "ConversationFlow/DeliveryGate/enforce_delivery_completion",
                projectRoot: projectRoot
            )
            let deliverySystem = ChatMessage(role: .system, content: deliveryPrompt)

            var followupMessages = historyCoordinator.messages + [deliverySystem]
            if planIsIncomplete {
                let planPrompt = try PromptRepository.shared.prompt(
                    key: "ConversationFlow/Corrections/plan_incomplete_continue",
                    projectRoot: projectRoot
                )
                followupMessages.append(ChatMessage(role: .system, content: planPrompt))
            }

            return try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: followupMessages,
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.delivery_gate
                ))
                .get()
        }

        if status == .done {
            // Guard against false "DONE" claims: only persist if checklist is already complete.
            if planProgress.isComplete, !planMarkdown.isEmpty,
                let completedPlan = PlanChecklistTracker.markAllPendingItemsCompleted(in: planMarkdown)
            {
                await ConversationPlanStore.shared.set(conversationId: conversationId, plan: completedPlan)
            }
        }

        // Default path: keep current response. Additional follow-up is only injected for
        // explicit NEEDS_WORK no-tool dropout scenarios handled above.
        return response
    }
}
