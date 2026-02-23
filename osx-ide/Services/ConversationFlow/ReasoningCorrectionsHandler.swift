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
                "Note: Your reasoning block was missing sections. Please ensure all sections (Analyze, Research, Plan, Reflect, Action, Delivery) are present in future responses."
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

        if status == .done {
            // Auto-mark plan as complete if the agent successfully delivered
            if let plan = await ConversationPlanStore.shared.get(
                conversationId: conversationId),
                !plan.isEmpty,
                let completedPlan = PlanChecklistTracker.markAllPendingItemsCompleted(in: plan)
            {
                await ConversationPlanStore.shared.set(
                    conversationId: conversationId, plan: completedPlan)
            }
        }

        // We no longer force a synchronous LLM followup here.
        // If the model stuck or didn't provide a correct status, it will be handled in the next turn
        // or during final response generation.
        return response
    }
}
