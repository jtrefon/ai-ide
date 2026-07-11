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
        mode: AIMode,
        projectRoot: URL,
        toolResults: [ChatMessage],
        runId: String,
        conversationId: String
    ) async throws -> AIServiceResponse {
        let split = ChatPromptBuilder.splitReasoning(from: response.content ?? "")
        let draft = split.content.trimmingCharacters(in: .whitespacesAndNewlines)

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
                    mode: mode,
                    projectRoot: projectRoot,
                    toolResults: toolResults,
                    runId: runId,
                    conversationId: conversationId,
                    followupReason: followupReason
                )
            }

            return response
        }

        return try await requestFinalResponse(
            response: response,
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
                    messages: historyCoordinator.requestMessages + [correctionSystem],
                    tools: [],
                    mode: followupMode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.final_response
                )
        )
        .get()

        let firstSplit = ChatPromptBuilder.splitReasoning(from: followup.content ?? "")
        let firstFollowupContent = firstSplit.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firstFollowupContent.isEmpty,
           !isGenericStatusMessage(firstFollowupContent),
           !ToolLoopUtilities.containsLiteralToolCallMarkup(firstFollowupContent) {
            return AIServiceResponse(content: firstSplit.content, toolCalls: nil, reasoning: firstSplit.reasoning ?? followup.reasoning)
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
                    messages: historyCoordinator.requestMessages + [ChatMessage(role: .system, content: retryPrompt)],
                    tools: [],
                    mode: followupMode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.final_response
                )
            )
            .get()

        let retrySplit = ChatPromptBuilder.splitReasoning(from: retryFollowup.content ?? "")
        let retryFollowupContent = retrySplit.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !retryFollowupContent.isEmpty,
           !isGenericStatusMessage(retryFollowupContent),
           !ToolLoopUtilities.containsLiteralToolCallMarkup(retryFollowupContent) {
            return AIServiceResponse(content: retrySplit.content, toolCalls: nil, reasoning: retrySplit.reasoning ?? retryFollowup.reasoning)
        }

        let deterministicSummary = await buildDeterministicFinalSummaryFallback(
            mode: mode,
            toolSummary: toolSummary,
            conversationId: conversationId,
            toolResults: toolResults
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
        mode: AIMode,
        toolSummary: String,
        conversationId: String,
        toolResults: [ChatMessage]
    ) async -> String {
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = formatPlanProgress(planMarkdown: planMarkdown)
        let checklist = PlanChecklistTracker.progress(in: planMarkdown)
        let hasIncompletePlan = checklist.total > 0 && !checklist.isComplete
        let completedTools = toolResults.filter { $0.isToolExecution && $0.toolStatus == .completed }
        let failedTools = toolResults.filter { $0.isToolExecution && $0.toolStatus == .failed }
        let completedToolNames = completedTools.compactMap(\.toolName)
        let touchedFiles = summarizeTouchedFiles(from: completedTools)
        let mutationTools = completedToolNames.filter(isMutationToolName(_:))

        var parts: [String] = []

        // Describe the work that was done
        if !mutationTools.isEmpty {
            let filePhrase = joinedList(touchedFiles)
            if filePhrase.isEmpty {
                parts.append("Modified files and completed work.")
            } else {
                parts.append("Modified: \(filePhrase).")
            }
        } else if !touchedFiles.isEmpty {
            parts.append("Inspected and analyzed: \(joinedList(touchedFiles)).")
        } else if !completedToolNames.isEmpty {
            let toolCounts = Dictionary(grouping: completedToolNames, by: { $0 }).map { "\($0.key) × \($0.value.count)" }.sorted().joined(separator: ", ")
            parts.append("Completed tools: \(toolCounts).")
        }

        if hasIncompletePlan {
            parts.append("Work is still incomplete (\(planProgress)).")
        }

        if !failedTools.isEmpty {
            let failedNames = Set(failedTools.compactMap(\.toolName)).sorted().joined(separator: ", ")
            parts.append("Tool failures: \(failedNames).")
        }

        let lines = compactToolSummaryLines(toolResults)
        if !lines.isEmpty {
            parts.append(lines)
        }

        if parts.isEmpty {
            return "I could not complete this task. Please try again with more specific instructions."
        }

        return parts.joined(separator: "\n\n")
    }

    /// Produces a compact, scan-friendly tool-activity summary for the user.
    /// Groups consecutive read_file results by file path and lists other
    /// tools with a short result preview.
    private func compactToolSummaryLines(_ toolResults: [ChatMessage]) -> String {
        let completed = toolResults.filter { $0.isToolExecution && $0.toolStatus == .completed }
        guard !completed.isEmpty else { return "" }

        var lines: [String] = ["Tools run:"]
        for result in completed {
            let tool = result.toolName ?? "unknown"
            let file = result.targetFile ?? ""
            let output = ToolLoopUtilities.toolOutputText(from: result).trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = output.isEmpty ? "" : " → \(output.prefix(120))"
            if !file.isEmpty {
                lines.append("  • \(tool): \(file)\(preview)")
            } else {
                lines.append("  • \(tool)\(preview)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func isReadOnlyInspectionToolName(_ toolName: String) -> Bool {
        [
            "read_file",
            "index_read_file",
            "list_files",
            "list_dir",
            "index_list_files",
            "search_files",
            "index_search_text",
            "index_search_symbols",
            "index_list_symbols"
        ].contains(toolName)
    }

    private func isMutationToolName(_ toolName: String) -> Bool {
        [
            "write_file",
            "write_files",
            "create_file",
            "replace_in_file",
            "delete_file",
            "multi_replace_file_content",
            "write_to_file"
        ].contains(toolName)
    }

    private func summarizeTouchedFiles(from toolResults: [ChatMessage]) -> [String] {
        var files: [String] = []
        var seen: Set<String> = []

        for result in toolResults {
            let candidate = result.targetFile?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let candidate, !candidate.isEmpty, seen.insert(candidate).inserted else { continue }
            files.append(candidate)
        }

        return files
    }

    private func joinedList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return "the relevant files"
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items[items.count - 1])"
        }
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
        // DeepSeek/OpenRouter native reasoning arrives via response.reasoning,
        // not embedded in the text content. Preserve it for the next request.
        let effectiveReasoning = response.reasoning ?? splitFinal.reasoning
        let sanitizedDisplay = ChatPromptBuilder.contentForDisplay(from: response.content ?? "")
        let trimmedContent = sanitizedDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent: String
        if !trimmedContent.isEmpty {
            displayContent = sanitizedDisplay
        } else {
            displayContent = ""
        }
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
            let draftMessage = historyCoordinator.getDraftMessage(id: draftId)
            let lastMessage = historyCoordinator.messages.last
            let isDraftAtEnd = (lastMessage?.id == draftId && lastMessage?.role == MessageRole.assistant)

            if isDraftAtEnd {
                let finalDraft = ChatMessage(
                    id: draftId,
                    role: MessageRole.assistant,
                    content: displayContent,
                    timestamp: draftMessage?.timestamp ?? Date(),
                    context: ChatMessageContentContext(reasoning: effectiveReasoning),
                    billing: draftMessage?.billing
                )
                historyCoordinator.setDraft(finalDraft)
                historyCoordinator.commitDraft()
            } else {
                historyCoordinator.clearDraft()
                historyCoordinator.append(
                    ChatMessage(
                        role: MessageRole.assistant,
                        content: displayContent,
                        context: ChatMessageContentContext(reasoning: effectiveReasoning),
                        billing: draftMessage?.billing
                    )
                )
            }
        } else if shouldAlwaysAppendPreservedHandoff || !isDuplicateOfLastAssistantMessage(content: displayContent) {
            historyCoordinator.append(
                ChatMessage(
                    role: MessageRole.assistant,
                    content: displayContent,
                    context: ChatMessageContentContext(reasoning: effectiveReasoning),
                    billing: historyCoordinator.messages.reversed().first {
                        $0.role == .assistant && $0.isDraft
                    }?.billing
                )
            )
        }

        let hasReasoning = (effectiveReasoning?.isEmpty == false)
        let contentLength = displayContent.count
        let reasoningText = effectiveReasoning

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
