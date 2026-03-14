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
        runId: String,
        conversationId: String
    ) async throws -> AIServiceResponse {
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if isDeterministicFallbackResponse(draft) {
            return response
        }

        if isIntermediateExecutionHandoffResponse(draft) {
            return response
        }

        if mode == .chat && !draft.isEmpty && toolResults.isEmpty {
            return response
        }

        if mode == .agent && !draft.isEmpty {
            let hasUnresolvedToolCalls = response.toolCalls?.isEmpty == false
            let isGenericContent = isGenericStatusMessage(draft)
            if hasUnresolvedToolCalls || isGenericContent {
                let followupReason: String
                if hasUnresolvedToolCalls {
                    followupReason = "Your previous response still included tool calls at finalization. Do not call tools now. Return only the final user-facing summary."
                } else {
                    followupReason = "Your previous response was too generic. Return a concise final user-facing summary grounded in completed work."
                }
                return try await requestFinalResponse(
                    response: response,
                    explicitContext: explicitContext,
                    mode: mode,
                    projectRoot: projectRoot,
                    toolResults: toolResults,
                    runId: runId,
                    conversationId: conversationId,
                    followupReason: followupReason
                )
            }
        }

        return try await requestFinalResponse(
            response: response,
            explicitContext: explicitContext,
            mode: mode,
            projectRoot: projectRoot,
            toolResults: toolResults,
            runId: runId,
            conversationId: conversationId,
            followupReason: nil
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

        if content.count < 50 {
            return true
        }

        return genericPatterns.contains { lowercased.contains($0) }
    }

    private func containsUnfinishedWorkSignals(_ content: String) -> Bool {
        let normalized = content.lowercased()
        let unfinishedSignals = [
            "needs_work",
            "needs work",
            "pending tasks remain",
            "continue with remaining",
            "continuing with the next",
            "unfinished",
            "remaining implementation",
            "next steps / risks: checklist items remain",
            "next steps/risks: checklist items remain"
        ]
        return unfinishedSignals.contains { normalized.contains($0) }
    }

    private func isDeterministicFallbackResponse(_ content: String) -> Bool {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("I wasn't able to generate a final response")
    }

    private func isIntermediateExecutionHandoffResponse(_ content: String) -> Bool {
        let normalized = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let handoffSignals = [
            "done -> next -> path:",
            "continue with remaining",
            "continuing with the next",
            "starting execution now",
            "pending tasks remain"
        ]
        return handoffSignals.contains { normalized.contains($0) }
    }

    private func requestFinalResponse(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        toolResults: [ChatMessage],
        runId: String,
        conversationId: String,
        followupReason: String?
    ) async throws -> AIServiceResponse {

        let toolSummary = ToolLoopUtilities.toolResultsSummaryText(toolResults)
        let resolvedReason: String
        if let followupReason {
            resolvedReason = followupReason
        } else if toolResults.isEmpty {
            resolvedReason = "You returned no user-visible response. Provide the final user-facing summary now without calling tools."
        } else {
            resolvedReason = "You returned no user-visible response after executing tools. Summarize the completed work now without calling tools."
        }

        let summaryPrompt = try await buildFinalResponsePrompt(
            followupReason: resolvedReason,
            toolSummary: toolSummary,
            projectRoot: projectRoot,
            conversationId: conversationId
        )

        let correctionSystem = ChatMessage(
            role: .system,
            content: summaryPrompt
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

        let firstFollowupContent = followup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstFollowupContent, !firstFollowupContent.isEmpty, !isGenericStatusMessage(firstFollowupContent) {
            return AIServiceResponse(content: followup.content, toolCalls: nil)
        }

        let retryPrompt = try await buildFinalResponsePrompt(
            followupReason: "Your previous final response still was not a usable final summary. Return a concise final user-facing summary grounded in completed work.",
            toolSummary: toolSummary,
            projectRoot: projectRoot,
            conversationId: conversationId
        )

        let retryFollowup = try await aiInteractionCoordinator
            .sendMessageWithRetry(
                AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [ChatMessage(role: .system, content: retryPrompt)],
                    explicitContext: explicitContext,
                    tools: [],
                    mode: followupMode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.final_response
                )
            )
            .get()

        let retryFollowupContent = retryFollowup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let retryFollowupContent, !retryFollowupContent.isEmpty, !isGenericStatusMessage(retryFollowupContent) {
            return AIServiceResponse(content: retryFollowup.content, toolCalls: nil)
        }

        let deterministicSummary = await buildDeterministicFinalSummaryFallback(
            toolSummary: toolSummary,
            conversationId: conversationId
        )
        return AIServiceResponse(content: deterministicSummary, toolCalls: nil)
    }

    private func buildFinalResponsePrompt(
        followupReason: String,
        toolSummary: String,
        projectRoot: URL,
        conversationId: String
    ) async throws -> String {
        let template = try PromptRepository.shared.prompt(
            key: "ConversationFlow/FinalResponse/final_response_summary",
            projectRoot: projectRoot
        )

        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let progress = formatPlanProgress(planMarkdown: planMarkdown)
        let sanitizedPlan = planMarkdown.isEmpty ? "None" : planMarkdown
        let sanitizedToolSummary = toolSummary.isEmpty ? "No tool outputs recorded." : toolSummary

        return template
            .replacingOccurrences(of: "{{followup_reason}}", with: followupReason)
            .replacingOccurrences(of: "{{tool_summary}}", with: sanitizedToolSummary)
            .replacingOccurrences(of: "{{plan_markdown}}", with: sanitizedPlan)
            .replacingOccurrences(of: "{{plan_progress}}", with: progress)
    }

    private func buildDeterministicFinalSummaryFallback(
        toolSummary: String,
        conversationId: String
    ) async -> String {
        let userObjective = historyCoordinator.messages
            .reversed()
            .first(where: { $0.role == .user })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Summarize current request"

        let oneLineObjective = userObjective
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = formatPlanProgress(planMarkdown: planMarkdown)
        let checklist = PlanChecklistTracker.progress(in: planMarkdown)
        let inferredNeedsWork = checklist.total > 0 && !checklist.isComplete
        let completionStatus = inferredNeedsWork ? "NEEDS_WORK" : "DONE"
        let workPerformed = toolSummary.isEmpty
            ? "None (explanation-only)."
            : "Summarized executed tool outputs from this run."
        let filesTouched = toolSummary.isEmpty ? "None" : "See tool recap in run logs"
        let nextSteps = completionStatus == "NEEDS_WORK"
            ? "Checklist items remain; continue execution for unfinished plan steps."
            : "None noted."

        return """
        Objective: \(oneLineObjective.isEmpty ? "Summarize current request" : oneLineObjective)
        Work performed: \(workPerformed)
        Files touched: \(filesTouched)
        Verification: Not Run
        Plan status: \(planProgress)
        Status: \(completionStatus)
        Next steps: \(nextSteps)
        """
    }

    private func formatPlanProgress(planMarkdown: String) -> String {
        guard !planMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No plan on record"
        }

        let progress = PlanChecklistTracker.progress(in: planMarkdown)
        guard progress.total > 0 else {
            return "Plan has no checklist items"
        }
        return "\(progress.completed)/\(progress.total) (\(progress.percentage)% complete)"
    }

    func appendFinalMessageAndLog(
        response: AIServiceResponse,
        conversationId: String,
        draftAssistantMessageId: String?
    ) {
        let splitFinal = ChatPromptBuilder.splitReasoning(
            from: response.content ?? "No response received.")
        let sanitizedDisplay = ChatPromptBuilder.contentForDisplay(from: response.content ?? "No response received.")
        let trimmedContent = sanitizedDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent =
            trimmedContent.isEmpty
            ? "Assistant returned no user-visible response. Please retry or rephrase."
            : sanitizedDisplay
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
        let responseContent = response.content ?? ""
        let parsedCompletionStatus = ChatPromptBuilder.deliveryStatus(from: responseContent)
        let completionStatus: ChatPromptBuilder.DeliveryStatus?
        if containsUnfinishedWorkSignals(responseContent) {
            completionStatus = .needsWork
        } else {
            completionStatus = parsedCompletionStatus
        }
        let completionStatusText: String
        switch completionStatus {
        case .done:
            completionStatusText = "done"
            Task {
                await completeRemainingPlanItems(conversationId: conversationId)
            }
        case .needsWork:
            completionStatusText = "needs_work"
        case .none:
            completionStatusText = "missing"
        }

        // Finalize the draft message if it exists, otherwise append a new one
        let shouldAlwaysAppendPreservedHandoff =
            completionStatus == .needsWork || isIntermediateExecutionHandoffResponse(responseContent)

        if let draftIdString = draftAssistantMessageId,
            let draftId = UUID(uuidString: draftIdString)
        {
            let lastMessage = historyCoordinator.messages.last
            let isDraftAtEnd = (lastMessage?.id == draftId && lastMessage?.role == MessageRole.assistant)

            if isDraftAtEnd {
                historyCoordinator.finalizeDraftMessage(
                    id: draftId,
                    content: displayContent,
                    reasoning: splitFinal.reasoning
                )
            } else {
                historyCoordinator.removeDraftMessage(id: draftId)
                historyCoordinator.append(
                    ChatMessage(
                        role: MessageRole.assistant,
                        content: displayContent,
                        context: ChatMessageContentContext(reasoning: splitFinal.reasoning)
                    )
                )
            }
        } else if shouldAlwaysAppendPreservedHandoff || !isDuplicateOfLastAssistantMessage(content: displayContent) {
            historyCoordinator.append(
                ChatMessage(
                    role: MessageRole.assistant,
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
                    "deliveryStatus": completionStatusText,
                ])
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.assistant_message",
                data: [
                    "content": displayContent,
                    "reasoning": reasoningText as Any,
                    "deliveryStatus": completionStatusText,
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
