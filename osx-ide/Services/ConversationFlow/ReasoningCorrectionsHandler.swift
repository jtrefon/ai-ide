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
        availableTools: [AITool]
    ) async throws -> AIServiceResponse {
        var currentResponse = response

        if ChatPromptBuilder.needsReasoningFormatCorrection(text: currentResponse.content ?? "") {
            let correctionSystem = ChatMessage(
                role: .system,
                content: "Your <ide_reasoning> block must include ALL six sections: Analyze, Research, Plan, Reflect, Action, Delivery. " +
                    "If a section is not applicable, write 'N/A' (do not omit it)."
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                ))
                .get()
        }

        if ChatPromptBuilder.isLowQualityReasoning(text: currentResponse.content ?? "") {
            let correctionSystem = ChatMessage(
                role: .system,
                content: "Your <ide_reasoning> block is too vague (placeholders like '...' are not allowed). " +
                    "Provide concise, concrete bullet points for EACH section: Analyze, Research, Plan, Reflect, Action, Delivery. " +
                    "If unknown, write 'N/A' and state what information is needed. " +
                    "If no action is needed, write 'None' in Action."
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                ))
                .get()
        }

        let split = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "")
        if split.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           split.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let correctionSystem = ChatMessage(
                role: .system,
                content: "You returned only a <ide_reasoning> block without a user-visible answer. " +
                    "Provide a final response in plain text now, without any <ide_reasoning> block."
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: [],
                    mode: .chat,
                    projectRoot: projectRoot
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
        availableTools: [AITool]
    ) async throws -> AIServiceResponse {
        guard mode == .agent else { return response }

        let content = response.content ?? ""
        let status = ChatPromptBuilder.deliveryStatus(from: content)
        if status == .done { return response }

        if status == nil {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return response }
            guard ChatPromptBuilder.shouldForceToolFollowup(content: trimmed) else { return response }
        }

        let correctionSystem = ChatMessage(
            role: .system,
            content: "In Agent mode, you must either (1) continue by calling tools to perform the work, or " +
                "(2) if the task is complete, explicitly mark Delivery: DONE and provide a user-visible response. " +
                "Continue the work now."
        )

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages + [correctionSystem],
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot
            ))
            .get()
    }
}
