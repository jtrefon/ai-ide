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
                    runId: runId,
                    conversationId: conversationId,
                    followupReason: "Your previous response was too generic and did not include the required Final Delivery Summary. Provide the mandated summary now."
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

        // If content is short or matches generic patterns
        if content.count < 50 {
            return true
        }

        return genericPatterns.contains { lowercased.contains($0) }
    }

    private func isDeterministicFallbackResponse(_ content: String) -> Bool {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("I wasn't able to generate a final response")
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
            resolvedReason = "You returned no user-visible response. Provide the mandated Final Delivery Summary now without calling tools."
        } else {
            resolvedReason = "You returned no user-visible response after executing tools. Summarize the work using the Final Delivery Summary scaffold without calling tools."
        }

        let summaryPrompt = try await buildFinalDeliveryPrompt(
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

        let followupContent = followup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent =
            followupContent?.isEmpty == false
            ? followup.content
            : response.content
        let resolvedContent =
            (finalContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? finalContent
            : "I wasn't able to generate a final response. "
                + "Here is a summary of tool outputs:\n\n\(toolSummary.isEmpty ? "No tools executed." : toolSummary)\n\n"
                + "Please retry or clarify the next step."
        return AIServiceResponse(content: resolvedContent, toolCalls: nil)
    }

    private func buildFinalDeliveryPrompt(
        followupReason: String,
        toolSummary: String,
        projectRoot: URL,
        conversationId: String
    ) async throws -> String {
        let template = try PromptRepository.shared.prompt(
            key: "ConversationFlow/FinalResponse/final_delivery_summary",
            defaultValue: Self.defaultFinalDeliveryPrompt,
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

    private static let defaultFinalDeliveryPrompt = """
# Final Delivery Contract

{{followup_reason}}

Before returning the final answer:

1. Emit the standard `<ide_reasoning>` block using the Reflection/Planning/Continuity schema (single-clause What/Where/How bullets; mention concrete files, commands, or tests). Keep it terse—this is still engineer-to-engineer pairing.
2. Immediately follow with **one** sentence covering `Done → Next → Path` so the user sees the closing state at a glance.
3. Do **not** call tools during this stage. This is a summary only.

After the reasoning block, output the final user-visible summary using the exact scaffold below:

```text
### Final Delivery Summary
- Objective: <restate the user objective in one clause>
- Work Performed: <concise bullet or clause describing the key changes>
- Files Touched: <comma-separated list of files or `None`>
- Verification: <tests/commands run, or `Not Run` + why>
- Next Steps / Risks: <what remains or any open risks>
- Undo / Recovery: <how to roll back (e.g., git checkout, revert instructions)>
- Plan Status: {{plan_progress}}

Delivery: <DONE or NEEDS_WORK>
```

Context you can reference (do **not** rewrite verbatim):

- **Tool recap**:

{{tool_summary}}

- **Plan markdown (read-only)**:

{{plan_markdown}}

Rules:

- If the plan is incomplete, be explicit about which checklist items remain.

- If no tools ran, say “Work Performed: None (explanation-only).”

- Never claim edits/tests that did not actually happen earlier in this run.

- Keep the entire response under 400 tokens—prioritize signal over fluff.
"""

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
