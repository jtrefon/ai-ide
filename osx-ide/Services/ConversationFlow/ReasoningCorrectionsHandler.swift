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
        var currentResponse = response

        if ChatPromptBuilder.needsReasoningFormatCorrection(text: currentResponse.content ?? "") {
            let promptText = PromptRepository.shared.prompt(
                key: "ConversationFlow/DeliveryGate/reasoning_format_correction",
                defaultValue: "Your <ide_reasoning> block must include ALL six sections: Analyze, Research, Plan, Reflect, Action, Delivery. " +
                    "If a section is not applicable, write 'N/A' (do not omit it).",
                projectRoot: projectRoot
            )
            let correctionSystem = ChatMessage(
                role: .system,
                content: promptText
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: [],
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.delivery_gate
                ))
                .get()
        }

        if ChatPromptBuilder.isLowQualityReasoning(text: currentResponse.content ?? "") {
            let promptText = PromptRepository.shared.prompt(
                key: "ConversationFlow/DeliveryGate/low_quality_reasoning",
                defaultValue: "Your <ide_reasoning> block is too vague (placeholders like '...' are not allowed). " +
                    "Provide concise, concrete bullet points for EACH section: Analyze, Research, Plan, Reflect, Action, Delivery. " +
                    "If unknown, write 'N/A' and state what information is needed. " +
                    "If no action is needed, write 'None' in Action.",
                projectRoot: projectRoot
            )
            let correctionSystem = ChatMessage(
                role: .system,
                content: promptText
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: [],
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.delivery_gate
                ))
                .get()
        }

        let split = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "")
        if split.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           split.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let promptText = PromptRepository.shared.prompt(
                key: "ConversationFlow/DeliveryGate/reasoning_only_no_answer",
                defaultValue: "You returned a <ide_reasoning> block without a user-visible answer. " +
                    "In Agent mode, you MUST still provide a user-visible response after </ide_reasoning>. " +
                    "Reply again now and include BOTH: (1) a complete <ide_reasoning> block and (2) the user-visible response after it.",
                projectRoot: projectRoot
            )
            let correctionSystem = ChatMessage(
                role: .system,
                content: promptText
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: [],
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.delivery_gate
                ))
                .get()
        }

        let implementationSplit = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "")
        if let reasoning = implementationSplit.reasoning,
           ChatPromptBuilder.reasoningContainsImplementation(reasoning) {
            let promptText = PromptRepository.shared.prompt(
                key: "ConversationFlow/DeliveryGate/no_implementation_in_reasoning",
                defaultValue: "Your <ide_reasoning> block contains implementation details (code, diffs, patches, or tool instructions). " +
                    "This is not allowed. Keep <ide_reasoning> concise and high-level only. " +
                    "Move ALL implementation details and code to the user-visible response AFTER </ide_reasoning>. " +
                    "Reply again now with: (1) a corrected <ide_reasoning> block and (2) the full user-visible response.",
                projectRoot: projectRoot
            )
            let correctionSystem = ChatMessage(role: .system, content: promptText)
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: [],
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.delivery_gate
                ))
                .get()
        }

        return currentResponse
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
        let executionExpected = ChatPromptBuilder.userRequestRequiresExecution(userInput: userInput)
        let status = ChatPromptBuilder.deliveryStatus(from: content)
        if status == .done {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasToolCalls = (response.toolCalls?.isEmpty == false)

            if !hasToolCalls,
               (
                    ChatPromptBuilder.indicatesWorkWasPerformed(content: trimmed)
                        || ChatPromptBuilder.shouldForceToolFollowup(content: trimmed)
                        || (executionExpected && ChatPromptBuilder.isRequestingUserInputForNextStep(content: trimmed))
                        || (executionExpected && !trimmed.isEmpty)
               ) {
                // Delivery claims completion, but execution was expected or the assistant implies it performed work.
                // Force an immediate followup instead of accepting DONE.
            } else {
                // Auto-mark plan as complete if the agent successfully delivered
                if let plan = await ConversationPlanStore.shared.get(conversationId: conversationId),
                   !plan.isEmpty,
                   let completedPlan = PlanChecklistTracker.markAllPendingItemsCompleted(in: plan) {
                    await ConversationPlanStore.shared.set(conversationId: conversationId, plan: completedPlan)
                }
                return response
            }
        }

        if status == nil {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return response }
            guard ChatPromptBuilder.indicatesWorkWasPerformed(content: trimmed)
                || ChatPromptBuilder.shouldForceToolFollowup(content: trimmed)
                || (executionExpected && ChatPromptBuilder.isRequestingUserInputForNextStep(content: trimmed))
                || (executionExpected && !trimmed.isEmpty)
            else { return response }
        }

        let correctionSystem = ChatMessage(
            role: .system,
            content: PromptRepository.shared.prompt(
                key: "ConversationFlow/DeliveryGate/enforce_delivery_completion",
                defaultValue: "In Agent mode, you must either (1) continue by calling tools to perform the work, or " +
                    "(2) if the task is complete, explicitly mark Delivery: DONE and provide a user-visible response. " +
                    "Continue the work now.",
                projectRoot: projectRoot
            )
        )

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages + [correctionSystem],
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop
            ))
            .get()
    }
}
