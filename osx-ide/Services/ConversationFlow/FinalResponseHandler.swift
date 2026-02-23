import Foundation

@MainActor
final class FinalResponseHandler {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
    }

    func requestFinalResponseIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        toolResults: [ChatMessage],
        runId: String
    ) async throws -> AIServiceResponse {
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // In Agent mode, always request a final response to ensure proper completion message
        // The model may return generic status text but we want a summary
        if mode == .agent && !draft.isEmpty {
            // Check if content is too generic (short or contains generic patterns)
            let isGenericContent = isGenericStatusMessage(draft)
            if isGenericContent {
                // Force final response generation for generic content
                return try await requestFinalResponse(
                    response: response,
                    explicitContext: explicitContext,
                    mode: mode,
                    projectRoot: projectRoot,
                    toolResults: toolResults,
                    runId: runId
                )
            }
        }

        guard draft.isEmpty else { return response }

        return try await requestFinalResponse(
            response: response,
            explicitContext: explicitContext,
            mode: mode,
            projectRoot: projectRoot,
            toolResults: toolResults,
            runId: runId
        )
    }

    private func isGenericStatusMessage(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        let genericPatterns = [
            "continuing",
            "next step",
            "execution step",
            "agent update",
            "processing",
            "working on",
            "analyzing",
            "gathering context",
        ]

        // If content is short or matches generic patterns
        if content.count < 50 {
            return true
        }

        return genericPatterns.contains { lowercased.contains($0) }
    }

    private func requestFinalResponse(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        toolResults: [ChatMessage],
        runId: String
    ) async throws -> AIServiceResponse {

        let toolSummary = ToolLoopUtilities.toolResultsSummaryText(toolResults)
        let correctionContent: String
        if toolResults.isEmpty {
            correctionContent =
                "You returned no user-visible response. Provide a final response in plain text now. "
                + "Do not call tools. Do not ask the user for more inputs (diffs, files, confirmations)."
        } else {
            correctionContent =
                "You returned no user-visible response after tool execution. "
                + "Provide a final response in plain text now summarizing what was done. "
                + "Do not call tools. Do not ask the user for more inputs (diffs, files, confirmations). "
                + "Do NOT repeat the raw tool outputs verbatim. Provide a high-level summary for the user.\n\nTool outputs:\n\(toolSummary)"
        }
        // Improve the prompt to get a better completion message
        let improvedCorrection =
            correctionContent + "\n\nIMPORTANT: Your final response should include:\n"
            + "1. Brief summary of what was accomplished\n"
            + "2. Files that were modified (if any)\n" + "3. Any errors or issues encountered\n"
            + "4. Next steps if task is incomplete"
        let correctionSystem = ChatMessage(
            role: .system,
            content: improvedCorrection
        )

        let followupMode: AIMode = (mode == .agent) ? .agent : .chat

        let followup =
            try await aiInteractionCoordinator
            .sendMessageWithRetry(
                AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: [],
                    mode: followupMode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.final_response
                )
            )
            .get()

        let followupContent = followup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent =
            followupContent?.isEmpty == false
            ? followup.content
            : response.content
        let resolvedContent =
            (finalContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? finalContent
            : "I wasn't able to generate a final response. "
                + "Here is a summary of tool outputs:\n\n\(toolSummary)\n\n"
                + "Please retry or clarify the next step."
        return AIServiceResponse(content: resolvedContent, toolCalls: nil)
    }

    func appendFinalMessageAndLog(
        response: AIServiceResponse,
        conversationId: String,
        draftAssistantMessageId: String?
    ) {
        let splitFinal = ChatPromptBuilder.splitReasoning(
            from: response.content ?? "No response received.")
        let trimmedContent = splitFinal.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent =
            trimmedContent.isEmpty
            ? "Assistant returned no user-visible response. Please retry or rephrase."
            : splitFinal.content
        if let reasoning = splitFinal.reasoning,
            let outcome = ChatPromptBuilder.reasoningOutcome(from: reasoning)
        {
            let outcomeMessage = """
                ReasoningOutcome:
                plan_delta: \(outcome.planDelta ?? "")
                next_action: \(outcome.nextAction ?? "")
                known_risks: \(outcome.knownRisks ?? "")
                delivery_state: \(outcome.deliveryState.rawValue)
                """
            historyCoordinator.append(
                ChatMessage(
                    role: .system,
                    content: outcomeMessage
                )
            )
        }
        let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: response.content ?? "")
        let deliveryStatusText: String
        switch deliveryStatus {
        case .done:
            deliveryStatusText = "done"
            Task {
                await completeRemainingPlanItems(conversationId: conversationId)
            }
        case .needsWork:
            deliveryStatusText = "needs_work"
        case .none:
            deliveryStatusText = "missing"
        }

        // Finalize the draft message if it exists, otherwise append a new one
        if let draftIdString = draftAssistantMessageId,
            let draftId = UUID(uuidString: draftIdString)
        {
            historyCoordinator.finalizeDraftMessage(
                id: draftId,
                content: displayContent,
                reasoning: splitFinal.reasoning
            )
        } else if !isDuplicateOfLastAssistantMessage(content: displayContent) {
            historyCoordinator.append(
                ChatMessage(
                    role: .assistant,
                    content: displayContent,
                    context: ChatMessageContentContext(reasoning: splitFinal.reasoning)
                )
            )
        }

        let hasReasoning = (splitFinal.reasoning?.isEmpty == false)
        let contentLength = displayContent.count
        let reasoningText = splitFinal.reasoning

        Task.detached(priority: .utility) {
            await AppLogger.shared.info(
                category: .conversation,
                message: "chat.assistant_message",
                context: AppLogger.LogCallContext(metadata: [
                    "conversationId": conversationId,
                    "contentLength": contentLength,
                    "hasReasoning": hasReasoning,
                    "deliveryStatus": deliveryStatusText,
                ])
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.assistant_message",
                data: [
                    "content": displayContent,
                    "reasoning": reasoningText as Any,
                    "deliveryStatus": deliveryStatusText,
                ]
            )
        }
    }

    private func isDuplicateOfLastAssistantMessage(content: String) -> Bool {
        guard
            let lastAssistant = historyCoordinator.messages.last(where: {
                $0.role == .assistant && ($0.toolCalls?.isEmpty ?? true)
            })
        else {
            return false
        }

        let lastContent = lastAssistant.content.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines)
        let newContent = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // Exact match
        if lastContent == newContent { return true }

        // Semantic match (ignore reasoning prefix if any)
        let lastSplit = ChatPromptBuilder.splitReasoning(from: lastContent)
        let newSplit = ChatPromptBuilder.splitReasoning(from: newContent)

        return lastSplit.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            == newSplit.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private func completeRemainingPlanItems(conversationId: String) async {
        guard let plan = await ConversationPlanStore.shared.get(conversationId: conversationId),
            !plan.isEmpty
        else {
            return
        }

        let progress = PlanChecklistTracker.progress(in: plan)

        // Only mark plan as complete if all items are actually done
        // Do NOT automatically mark remaining items as complete - this was causing false completion
        if progress.isComplete {
            // Plan is truly complete - this is fine
            if let completedPlan = PlanChecklistTracker.markAllPendingItemsCompleted(in: plan) {
                await ConversationPlanStore.shared.set(
                    conversationId: conversationId, plan: completedPlan)
            }
        } else {
            // Plan NOT complete - log warning and do NOT mark items as done
            // Don't call markAllPendingItemsCompleted - that was the bug!
            await AppLogger.shared.warning(
                category: .conversation,
                message: "plan.marked_complete_despite_incomplete",
                context: AppLogger.LogCallContext(metadata: [
                    "conversationId": conversationId,
                    "completedItems": String(progress.completed),
                    "totalItems": String(progress.total),
                    "completionPercentage": String(progress.percentage),
                ])
            )
        }
    }
}
