import Foundation

@MainActor
final class ToolLoopHandler {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let toolExecutionCoordinator: ToolExecutionCoordinator

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        toolExecutionCoordinator: ToolExecutionCoordinator
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
        self.toolExecutionCoordinator = toolExecutionCoordinator
    }

    func handleToolLoopIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        cancelledToolCallIds: @escaping () -> Set<String>,
        runId: String,
        userInput: String
    ) async throws -> ToolLoopResult {
        guard mode == .agent else {
            return ToolLoopResult(response: response, lastToolCalls: [], lastToolResults: [])
        }

        var currentResponse = response
        var toolIteration = 0
        var lastToolCalls: [AIToolCall] = []
        var lastToolResults: [ChatMessage] = []
        var consecutiveEmptyToolCallResponses = 0
        var previousToolBatchSignature: String?
        var repeatedToolBatchCount = 0
        var previousNoToolCallContentSignature = normalizedNoToolCallContentSignature(currentResponse.content)
        var repeatedNoToolCallContentCount = 0
        var consecutiveReadOnlyToolIterations = 0
        var previousReadOnlyToolBatchSignature: String?
        var repeatedReadOnlyToolBatchCount = 0
        var previousWriteTargetSignature: String?
        var repeatedWriteTargetCount = 0
        let maxIterations = (mode == .agent) ? ToolLoopConstants.maxAgentIterations : ToolLoopConstants.maxNonAgentIterations

        if mode == .agent,
           currentResponse.toolCalls?.isEmpty ?? true,
           !availableTools.isEmpty {
            await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.pre_loop", data: [
                "runId": runId,
                "hasToolCalls": false,
                "contentLength": currentResponse.content?.count ?? 0
            ])

            let focusedMessages = await buildFocusedExecutionMessages(
                userInput: userInput,
                conversationId: conversationId,
                projectRoot: projectRoot
            )

            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: focusedMessages,
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.tool_loop
                ))
                .get()
        }

        while let toolCalls = currentResponse.toolCalls,
              !toolCalls.isEmpty,
              toolIteration < maxIterations {
            toolIteration += 1
            let uniqueToolCalls = deduplicateToolCalls(toolCalls)
            lastToolCalls = uniqueToolCalls

            let currentToolBatchSignature = toolBatchSignature(uniqueToolCalls)
            if let previousToolBatchSignature,
               previousToolBatchSignature == currentToolBatchSignature {
                repeatedToolBatchCount += 1
            } else {
                repeatedToolBatchCount = 0
            }
            previousToolBatchSignature = currentToolBatchSignature

            let currentWriteTargetSignature = writeTargetSignature(toolCalls: uniqueToolCalls)
            if let currentWriteTargetSignature,
               let previousWriteTargetSignature,
               currentWriteTargetSignature == previousWriteTargetSignature {
                repeatedWriteTargetCount += 1
            } else {
                repeatedWriteTargetCount = 0
            }
            previousWriteTargetSignature = currentWriteTargetSignature

            if repeatedWriteTargetCount >= ToolLoopConstants.repeatedWriteTargetStallThreshold {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_write_target_stall", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "repeatedWriteTargetCount": repeatedWriteTargetCount + 1,
                    "writeTargetSignature": currentWriteTargetSignature ?? "none"
                ])

                currentResponse = try await requestDiversifiedExecutionForRepeatedWriteTargets(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    runId: runId,
                    writeTargetSignature: currentWriteTargetSignature ?? "(none)",
                    availableTools: availableTools
                )

                repeatedWriteTargetCount = 0
                previousWriteTargetSignature = nil
                continue
            }

            if shouldStopForReadOnlyToolLoopStall(
                toolCalls: uniqueToolCalls,
                consecutiveReadOnlyToolIterations: &consecutiveReadOnlyToolIterations,
                previousReadOnlyToolBatchSignature: &previousReadOnlyToolBatchSignature,
                repeatedReadOnlyToolBatchCount: &repeatedReadOnlyToolBatchCount
            ) {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_read_only_stall", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "consecutiveReadOnlyIterations": consecutiveReadOnlyToolIterations,
                    "repeatedReadOnlyBatchCount": repeatedReadOnlyToolBatchCount + 1,
                    "toolCalls": uniqueToolCalls.count
                ])
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: lastToolResults,
                    runId: runId,
                    availableTools: availableTools
                )
                break
            }

            if repeatedToolBatchCount >= ToolLoopConstants.repeatedBatchStallThreshold {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_batch_stall", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "repeatedBatchCount": repeatedToolBatchCount + 1,
                    "toolCalls": uniqueToolCalls.count
                ])
                ToolExecutionTelemetry.shared.recordRepeatedBatch()
                // For repeated batch stall, skip execution transition and go directly to final response
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: lastToolResults,
                    runId: runId,
                    availableTools: nil // No tools - skip execution transition for repeated batch
                )
                break
            }

            await AIToolTraceLogger.shared.log(type: "chat.tool_loop_iteration", data: [
                "mode": mode.rawValue,
                "iteration": toolIteration,
                "toolCalls": uniqueToolCalls.count,
                "deduplicatedToolCalls": toolCalls.count - uniqueToolCalls.count
            ])
            
            // Record telemetry
            ToolExecutionTelemetry.shared.recordIteration()
            let dedupCount = toolCalls.count - uniqueToolCalls.count
            if dedupCount > 0 {
                ToolExecutionTelemetry.shared.recordDeduplicatedToolCalls(count: dedupCount)
            }

            let split = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "")
            let hasModelStepUpdate = !split.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasReasoning = !(split.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning),
                tool: ChatMessageToolContext(toolCalls: uniqueToolCalls)
            )
            if hasModelStepUpdate || hasReasoning {
                historyCoordinator.append(assistantMsg)
            }

            logAssistantToolCalls(
                conversationId: conversationId,
                content: split.content,
                toolCalls: uniqueToolCalls
            )

            markCancelledToolCalls(toolCalls: uniqueToolCalls, cancelledToolCallIds: cancelledToolCallIds())

            let statusSummary = buildGenericToolExecutionStatusSummary()
            if !hasModelStepUpdate {
                historyCoordinator.append(ChatMessage(
                    role: .assistant,
                    content: statusSummary
                ))
            }

            let toolResults = await toolExecutionCoordinator.executeToolCalls(
                uniqueToolCalls,
                availableTools: availableTools,
                conversationId: conversationId
            ) { [weak self] progressMsg in
                guard let self else { return }
                if progressMsg.isToolExecution {
                    self.historyCoordinator.upsertToolExecutionMessage(progressMsg)
                } else {
                    self.historyCoordinator.append(progressMsg)
                }
            }

            for msg in toolResults {
                if msg.isToolExecution {
                    historyCoordinator.upsertToolExecutionMessage(msg)
                    if msg.toolStatus == .completed {
                        ToolExecutionTelemetry.shared.recordSuccessfulExecution()
                    }
                } else {
                    historyCoordinator.append(msg)
                }
            }

            lastToolResults = toolResults
            await advancePlanProgressIfNeeded(
                conversationId: conversationId,
                toolResults: toolResults
            )

            await ToolLoopUtilities.appendRunSnapshot(
                runId: runId,
                conversationId: conversationId,
                phase: "tool_loop",
                iteration: toolIteration,
                userInput: userInput,
                assistantDraft: currentResponse.content,
                failureReason: ToolLoopUtilities.failureReason(from: toolResults),
                toolCalls: uniqueToolCalls,
                toolResults: toolResults
            )

            let failureRecoveryMessage = toolFailureRecoveryMessage(
                toolCalls: uniqueToolCalls,
                toolResults: toolResults
            )
            let toolLoopContext = toolLoopContextMessage(toolResults: toolResults)
            var followupMessages = historyCoordinator.messages
            
            if let toolLoopContext {
                followupMessages.append(toolLoopContext)
            }
            if let failureRecoveryMessage {
                followupMessages.append(failureRecoveryMessage)
            }
            followupMessages.append(toolLoopStepUpdateInstructionMessage(consecutiveReadOnlyIterations: consecutiveReadOnlyToolIterations))
            
            followupMessages = MessageTruncationPolicy.truncateForModel(followupMessages)

            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: followupMessages,
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.tool_loop
                ))
                .get()

            if updateRepeatedNoToolCallContentState(
                response: currentResponse,
                previousSignature: &previousNoToolCallContentSignature,
                repeatedCount: &repeatedNoToolCallContentCount
            ) {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_no_tool_call_content_stall", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "repeatedCount": repeatedNoToolCallContentCount + 1,
                    "contentLength": currentResponse.content?.count ?? 0
                ])
                ToolExecutionTelemetry.shared.recordRepeatedContent()
                let hasTextualPattern = isTextualToolCallPattern(currentResponse.content)
                ToolExecutionTelemetry.shared.recordResponseWithoutToolCalls(hasTextualPattern: hasTextualPattern)
                // For repeated content stall, skip execution transition and go directly to final response
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: lastToolResults,
                    runId: runId,
                    availableTools: nil // No tools - skip execution transition for repeated content
                )
                break
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               (
                    ChatPromptBuilder.shouldForceToolFollowup(content: content)
                    || ChatPromptBuilder.shouldForceExecutionFollowup(
                        userInput: userInput,
                        content: content,
                        hasToolCalls: false
                    )
               ),
               let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user }) {
                await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.tool_loop", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "hasToolCalls": false,
                    "contentLength": content.count
                ])
                let promptText = PromptRepository.shared.prompt(
                    key: "ConversationFlow/Corrections/force_tool_followup",
                    defaultValue: "You indicated you will implement changes, but you returned no tool calls. " +
                        "In Agent mode, you MUST now proceed by calling the appropriate tools. " +
                        "Return tool calls now.",
                    projectRoot: projectRoot
                )
                let followupSystem = ChatMessage(
                    role: .system,
                    content: promptText
                )
                currentResponse = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: historyCoordinator.messages + [followupSystem, lastUserMessage],
                        explicitContext: explicitContext,
                        tools: availableTools,
                        mode: mode,
                        projectRoot: projectRoot,
                        runId: runId,
                        stage: AIRequestStage.tool_loop
                    ))
                    .get()

                if updateRepeatedNoToolCallContentState(
                    response: currentResponse,
                    previousSignature: &previousNoToolCallContentSignature,
                    repeatedCount: &repeatedNoToolCallContentCount
                ) {
                    await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_no_tool_call_content_stall", data: [
                        "runId": runId,
                        "iteration": toolIteration,
                        "repeatedCount": repeatedNoToolCallContentCount + 1,
                        "contentLength": currentResponse.content?.count ?? 0
                    ])
                    currentResponse = try await requestFinalResponseForStalledToolLoop(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        toolResults: lastToolResults,
                        runId: runId,
                        availableTools: availableTools
                    )
                    break
                }
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               ChatPromptBuilder.isRequestingUserInputForNextStep(content: content) {
                let promptText = PromptRepository.shared.prompt(
                    key: "ConversationFlow/Corrections/no_user_input_next_step",
                    defaultValue: "In Agent mode, do not ask the user for additional inputs (diffs, files, confirmations) as a next step. " +
                        "Proceed autonomously using the available tools and make reasonable assumptions. " +
                        "If multiple options exist, pick the safest default and continue. Return tool calls now if needed.",
                    projectRoot: projectRoot
                )
                let followupSystem = ChatMessage(
                    role: .system,
                    content: promptText
                )
                currentResponse = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: historyCoordinator.messages + [followupSystem],
                        explicitContext: explicitContext,
                        tools: availableTools,
                        mode: mode,
                        projectRoot: projectRoot,
                        runId: runId,
                        stage: AIRequestStage.tool_loop
                    ))
                    .get()

                if updateRepeatedNoToolCallContentState(
                    response: currentResponse,
                    previousSignature: &previousNoToolCallContentSignature,
                    repeatedCount: &repeatedNoToolCallContentCount
                ) {
                    await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_no_tool_call_content_stall", data: [
                        "runId": runId,
                        "iteration": toolIteration,
                        "repeatedCount": repeatedNoToolCallContentCount + 1,
                        "contentLength": currentResponse.content?.count ?? 0
                    ])
                    currentResponse = try await requestFinalResponseForStalledToolLoop(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        toolResults: lastToolResults,
                        runId: runId,
                        availableTools: availableTools
                    )
                    break
                }
            }

            let trimmedContent = currentResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedContent.isEmpty, currentResponse.toolCalls?.isEmpty == false {
                consecutiveEmptyToolCallResponses += 1
            } else {
                consecutiveEmptyToolCallResponses = 0
            }

            if consecutiveEmptyToolCallResponses >= ToolLoopConstants.emptyResponseStallThreshold {
                // For empty response stall, skip execution transition
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: lastToolResults,
                    runId: runId,
                    availableTools: nil // No tools - skip execution transition for empty response stall
                )
                break
            }
        }

        if mode == .agent,
           currentResponse.toolCalls?.isEmpty ?? true,
           !availableTools.isEmpty,
           await shouldForceContinuationForIncompletePlan(conversationId: conversationId, content: currentResponse.content) {
            currentResponse = try await requestContinuationForIncompletePlan(
                explicitContext: explicitContext,
                projectRoot: projectRoot,
                mode: mode,
                availableTools: availableTools,
                runId: runId
            )
        }

        return ToolLoopResult(
            response: currentResponse,
            lastToolCalls: lastToolCalls,
            lastToolResults: lastToolResults
        )
    }

    private func logAssistantToolCalls(conversationId: String, content: String, toolCalls: [AIToolCall]) {
        let toolCallsCount = toolCalls.count
        let toolCallsMetadata = toolCalls.map {
            [
                "id": $0.id,
                "name": $0.name
            ]
        }

        Task.detached(priority: .utility) {
            await AppLogger.shared.info(
                category: .conversation,
                message: "chat.assistant_tool_calls",
                context: AppLogger.LogCallContext(metadata: [
                    "conversationId": conversationId,
                    "toolCalls": toolCallsCount
                ])
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.assistant_tool_calls",
                data: [
                    "content": content,
                    "toolCalls": toolCallsMetadata
                ]
            )
        }
    }

    private func markCancelledToolCalls(toolCalls: [AIToolCall], cancelledToolCallIds: Set<String>) {
        for call in toolCalls where cancelledToolCallIds.contains(call.id) {
            historyCoordinator.updateMessageStatus(
                toolCallId: call.id,
                status: .failed,
                content: "Cancelled by user"
            )
        }
    }

    private func toolFailureRecoveryMessage(
        toolCalls: [AIToolCall],
        toolResults: [ChatMessage]
    ) -> ChatMessage? {
        let failedToolResults = toolResults.filter {
            $0.isToolExecution && $0.toolStatus == .failed
        }
        guard !failedToolResults.isEmpty else { return nil }

        let failedOutputs = failedToolResults.map { ToolLoopUtilities.toolOutputText(from: $0) }
        let hasTimeoutFailure = failedOutputs.contains { $0.localizedCaseInsensitiveContains("timed out") }
        let hasCancelledFailure = failedOutputs.contains { $0.localizedCaseInsensitiveContains("cancelled") }

        let toolCallIndex = Dictionary(
            uniqueKeysWithValues: toolCalls.map { ($0.id, $0) }
        )
        let failureDetails = failedToolResults.map { result in
            let toolName = result.toolName ?? "unknown_tool"
            let toolCallId = result.toolCallId ?? "unknown_call"
            let argumentKeys = toolCallIndex[toolCallId]?.arguments.keys.sorted() ?? []
            let argumentSummary = argumentKeys.isEmpty
                ? "arguments: none"
                : "argument keys: \(argumentKeys.joined(separator: ", "))"
            let output = ToolLoopUtilities.toolOutputText(from: result)
            return "- \(toolName) (\(toolCallId)): \(output) [\(argumentSummary)]"
        }

        var recoveryLines: [String] = [
            "Tool execution failures detected.",
            "Review the failures below and adjust your approach.",
            "If a failure is environmental, network, or resource-related, propose a fallback plan or use different parameters.",
            "Do not repeat the same failing call without changes."
        ]

        if hasTimeoutFailure || hasCancelledFailure {
            recoveryLines.append(contentsOf: [
                "",
                "IMPORTANT (timeouts/cancellations): One or more tools were terminated for safety to prevent the agent from getting stuck.",
                "This usually indicates a non-returning command (watcher/server), an interactive prompt, or a command producing no progress.",
                "",
                "Recovery instructions:",
                "- Do NOT re-run the same command unchanged.",
                "- Prefer short, finite commands that return control.",
                "- Use non-interactive flags and bounded output.",
                "- If you need long work, break it into smaller steps (diagnostics first, then targeted execution)."
            ])
        }

        let systemMessage = ChatMessage(
            role: .system,
            content: (recoveryLines + ["", failureDetails.joined(separator: "\n")]).joined(separator: "\n")
        )
        return systemMessage
    }

    private func toolLoopContextMessage(toolResults: [ChatMessage]) -> ChatMessage? {
        guard !toolResults.isEmpty else { return nil }
        return ChatMessage(
            role: .system,
            content: "Tool execution loop context: The following tool messages are system tool outputs. " +
                "They are not user-visible. Use them to decide next tool calls or provide a final response. " +
                "Do not echo raw tool envelopes."
        )
    }

    private func buildGenericToolExecutionStatusSummary() -> String {
        // This is shown when model doesn't provide a user-facing update
        // Keep it brief and informative
        return "Continuing with next step..."
    }

    private func toolLoopStepUpdateInstructionMessage(consecutiveReadOnlyIterations: Int = 0) -> ChatMessage {
        var content = "Before returning tool calls, include either (a) a short <ide_reasoning> block with Analyze/Plan/Action bullets or (b) at minimum one short user-facing update sentence explaining what you will do next and why. Then return tool calls. Do not ask the user for additional input."
        
        // Add nudge after consecutive read-only tool iterations
        if consecutiveReadOnlyIterations >= ToolLoopConstants.readOnlyIterationNudgeThreshold {
            content += "\n\nIMPORTANT: You have made \(consecutiveReadOnlyIterations) consecutive read-only tool calls. " +
                "If the task requires changes to files, transition to execution now using write_file, replace_in_file, or run_command. " +
                "Do not continue gathering context if you have enough information to proceed."
        }
        
        return ChatMessage(
            role: .system,
            content: content
        )
    }

    private func shouldForceContinuationForIncompletePlan(conversationId: String, content: String?) async -> Bool {
        guard let plan = await ConversationPlanStore.shared.get(conversationId: conversationId),
              !plan.isEmpty else {
            return false
        }

        let progress = PlanChecklistTracker.progress(in: plan)
        guard progress.total > 0, !progress.isComplete else {
            return false
        }

        let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: content ?? "")
        return deliveryStatus != .done
    }

    private func updateRepeatedNoToolCallContentState(
        response: AIServiceResponse,
        previousSignature: inout String?,
        repeatedCount: inout Int
    ) -> Bool {
        guard response.toolCalls?.isEmpty ?? true,
              let signature = normalizedNoToolCallContentSignature(response.content) else {
            previousSignature = nil
            repeatedCount = 0
            return false
        }

        if signature == previousSignature {
            repeatedCount += 1
        } else {
            previousSignature = signature
            repeatedCount = 0
        }

        if isTextualToolCallPattern(response.content) {
            return repeatedCount >= ToolLoopConstants.textualPatternRepeatedThreshold
        }

        return repeatedCount >= ToolLoopConstants.normalPatternRepeatedThreshold
    }

    private func normalizedNoToolCallContentSignature(_ content: String?) -> String? {
        guard let content else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return trimmed
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func isTextualToolCallPattern(_ content: String?) -> Bool {
        guard let content else { return false }
        let text = content.lowercased()
        if text.isEmpty { return false }
        return text.contains("tool calls:") || text.contains("tool call:")
    }

    private func shouldStopForReadOnlyToolLoopStall(
        toolCalls: [AIToolCall],
        consecutiveReadOnlyToolIterations: inout Int,
        previousReadOnlyToolBatchSignature: inout String?,
        repeatedReadOnlyToolBatchCount: inout Int
    ) -> Bool {
        guard !toolCalls.isEmpty else {
            consecutiveReadOnlyToolIterations = 0
            previousReadOnlyToolBatchSignature = nil
            repeatedReadOnlyToolBatchCount = 0
            return false
        }

        let isReadOnlyBatch = toolCalls.allSatisfy { readOnlyLoopToolNames.contains($0.name) }
        guard isReadOnlyBatch else {
            consecutiveReadOnlyToolIterations = 0
            previousReadOnlyToolBatchSignature = nil
            repeatedReadOnlyToolBatchCount = 0
            return false
        }

        consecutiveReadOnlyToolIterations += 1
        let signature = toolBatchSignature(toolCalls)
        if signature == previousReadOnlyToolBatchSignature {
            repeatedReadOnlyToolBatchCount += 1
        } else {
            previousReadOnlyToolBatchSignature = signature
            repeatedReadOnlyToolBatchCount = 0
        }

        return consecutiveReadOnlyToolIterations >= ToolLoopConstants.readOnlyIterationStallThreshold
            || repeatedReadOnlyToolBatchCount >= ToolLoopConstants.repeatedReadOnlyBatchStallThreshold
    }

    private var readOnlyLoopToolNames: Set<String> {
        [
            "read_file",
            "index_read_file",
            "index_find_files",
            "index_list_files",
            "index_list_symbols",
            "index_list_memories",
            "checkpoint_list"
        ]
    }

    private func requestContinuationForIncompletePlan(
        explicitContext: String?,
        projectRoot: URL,
        mode: AIMode,
        availableTools: [AITool],
        runId: String
    ) async throws -> AIServiceResponse {
        let followupSystem = ChatMessage(
            role: .system,
            content: "The implementation plan is not complete yet. Continue with the next unfinished checklist item. Include a short reasoning/update, then return tool calls. Do not finish with a final answer yet."
        )
        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages + [followupSystem],
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop
            ))
            .get()
    }

    private func advancePlanProgressIfNeeded(conversationId: String, toolResults: [ChatMessage]) async {
        let hasSuccessfulToolResult = toolResults.contains {
            $0.isToolExecution && $0.toolStatus == .completed
        }
        guard hasSuccessfulToolResult else { return }

        guard let currentPlan = await ConversationPlanStore.shared.get(conversationId: conversationId),
              !currentPlan.isEmpty,
              let updatedPlan = PlanChecklistTracker.markNextPendingItemCompleted(in: currentPlan) else {
            return
        }

        await ConversationPlanStore.shared.set(conversationId: conversationId, plan: updatedPlan)
        replaceLatestPlanMessage(with: updatedPlan)
    }

    private func replaceLatestPlanMessage(with updatedPlan: String) {
        let messages = historyCoordinator.messages
        guard let lastPlanIndex = messages.lastIndex(where: {
            $0.role == .assistant && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# Implementation Plan")
        }) else {
            return
        }

        historyCoordinator.replaceMessage(at: lastPlanIndex, with: ChatMessage(
            role: .assistant,
            content: updatedPlan
        ))
    }

    private func buildFocusedExecutionMessages(
        userInput: String,
        conversationId: String,
        projectRoot: URL
    ) async -> [ChatMessage] {
        let plan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""

        var parts: [String] = []
        parts.append("You are a coding assistant. Your job right now is to execute the task with tools.")
        parts.append("If helpful, include a concise <ide_reasoning> block before your update.")
        parts.append("RESPONSE FORMAT (required):")
        parts.append("1) Optional: <ide_reasoning> with short Analyze/Plan/Action bullets only.")
        parts.append("2) Then one short user-facing update sentence stating what you will do next and why.")
        parts.append("3) Then return the tool calls needed for that step.")
        parts.append("Keep reasoning and update concise. Do not ask the user for input.")

        if !plan.isEmpty {
            parts.append("Plan:\n\(plan)")
        }

        return [
            ChatMessage(role: .system, content: parts.joined(separator: "\n\n")),
            ChatMessage(role: .user, content: userInput)
        ]
    }

    private func requestFinalResponseForStalledToolLoop(
        explicitContext: String?,
        projectRoot: URL,
        mode: AIMode,
        userInput: String,
        toolResults: [ChatMessage],
        runId: String,
        availableTools: [AITool]? = nil
    ) async throws -> AIServiceResponse {
        let toolSummary = ToolLoopUtilities.toolResultsSummaryText(toolResults)
        
        // If we have execution tools available, try to force execution transition first
        if let availableTools, mode == .agent {
            let executionTools = availableTools.filter { !readOnlyLoopToolNames.contains($0.name) }
            
            if !executionTools.isEmpty {
                // Log the execution transition attempt
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_execution_transition", data: [
                    "runId": runId,
                    "executionToolsCount": executionTools.count,
                    "toolSummaryLength": toolSummary.count
                ])
                
                let executionPrompt = ChatMessage(
                    role: .system,
                    content: """
                    You have been gathering context with read-only tools but haven't made any changes yet.
                    The user's request requires EXECUTION, not just exploration.
                    
                    You MUST now transition to execution:
                    1. Use write_files for multi-file scaffolding and coordinated creation
                    2. Use write_file only for single-file creation/overwrite
                    3. Use replace_in_file to modify existing files
                    4. Use run_command for build/test commands
                    
                    Do NOT call more read-only tools (read_file, index_*, list_*).
                    Proceed with execution now using the available write/edit tools.
                    
                    User request: \(userInput)
                    
                    Context gathered:
                    \(toolSummary)
                    """
                )
                
                let executionResponse = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: historyCoordinator.messages + [executionPrompt],
                        explicitContext: explicitContext,
                        tools: executionTools,
                        mode: mode,
                        projectRoot: projectRoot,
                        runId: runId,
                        stage: AIRequestStage.tool_loop
                    ))
                    .get()
                
                // If model returned execution tool calls, use them
                if let toolCalls = executionResponse.toolCalls, !toolCalls.isEmpty {
                    let hasExecutionTool = toolCalls.contains { !readOnlyLoopToolNames.contains($0.name) }
                    if hasExecutionTool {
                        return executionResponse
                    }
                }
            }
        }
        
        // Fallback: request final response without tools
        let correctionSystem = ChatMessage(
            role: .system,
            content: "You kept calling tools without producing a user-visible response. " +
                "Stop calling tools now and provide a final response in plain text.\n\n" +
                "User request:\n\(userInput)\n\nTool outputs:\n\(toolSummary)"
        )
        let correctionUser = ChatMessage(
            role: .user,
            content: "Provide the final response now."
        )

        let followupMode: AIMode = (mode == .agent) ? .agent : .chat
        let followup = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [correctionSystem, correctionUser],
                explicitContext: explicitContext,
                tools: [],
                mode: followupMode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.final_response
            ))
            .get()

        let followupContent = followup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = followupContent?.isEmpty == false
            ? followup.content
            : "I attempted to gather context via tools but did not receive a complete response. Please retry."
        return AIServiceResponse(content: finalContent, toolCalls: nil)
    }

    private func deduplicateToolCalls(_ toolCalls: [AIToolCall]) -> [AIToolCall] {
        var seenSignatures = Set<String>()
        var uniqueCalls: [AIToolCall] = []

        for toolCall in toolCalls {
            let signature = toolCallSignature(toolCall)
            if seenSignatures.insert(signature).inserted {
                uniqueCalls.append(toolCall)
            }
        }

        return uniqueCalls
    }

    private func toolBatchSignature(_ toolCalls: [AIToolCall]) -> String {
        toolCalls
            .map(toolCallSignature)
            .sorted()
            .joined(separator: "||")
    }

    private func toolCallSignature(_ toolCall: AIToolCall) -> String {
        let argumentsString: String
        if let data = try? JSONSerialization.data(withJSONObject: toolCall.arguments, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            argumentsString = json
        } else {
            let fallback = toolCall.arguments
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\(String(describing: $0.value))" }
                .joined(separator: "&")
            argumentsString = fallback
        }

        return "\(toolCall.name)|\(argumentsString)"
    }

    private func writeTargetSignature(toolCalls: [AIToolCall]) -> String? {
        var targets: [String] = []

        for toolCall in toolCalls {
            switch toolCall.name {
            case "write_file", "replace_in_file", "create_file", "delete_file":
                if let path = toolCall.arguments["path"] as? String,
                   !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    targets.append(path)
                }
            case "write_files":
                if let files = toolCall.arguments["files"] as? [[String: Any]] {
                    for file in files {
                        if let path = file["path"] as? String,
                           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            targets.append(path)
                        }
                    }
                }
            default:
                continue
            }
        }

        guard !targets.isEmpty else { return nil }
        return targets.sorted().joined(separator: "||")
    }

    private func requestDiversifiedExecutionForRepeatedWriteTargets(
        explicitContext: String?,
        projectRoot: URL,
        mode: AIMode,
        userInput: String,
        runId: String,
        writeTargetSignature: String,
        availableTools: [AITool]
    ) async throws -> AIServiceResponse {
        let correctionSystem = ChatMessage(
            role: .system,
            content: """
            You are repeatedly writing the same target files without completing the user's request.

            Repeated write targets: \(writeTargetSignature)

            You MUST diversify execution now:
            1. Do NOT rewrite the same target files unless strictly necessary.
            2. Create or modify the remaining missing files required by the user request.
            3. Return concrete tool calls that advance completion.

            User request:
            \(userInput)
            """
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
