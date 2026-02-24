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
        var previousAssistantUpdateSignature: String?
        var previousToolCallSignatures: Set<String> = []
        var previouslyFailedToolCallSignatures: Set<String> = []
        var previouslyCompletedToolCallSignatures: Set<String> = []
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
            let currentToolCallSignatures = Set(uniqueToolCalls.map(toolCallSignature))
            let repeatedCompletedSignatures = currentToolCallSignatures.intersection(previouslyCompletedToolCallSignatures)
            if !repeatedCompletedSignatures.isEmpty {
                ToolExecutionTelemetry.shared.recordRepeatedToolCallSignatures(count: repeatedCompletedSignatures.count)
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_completed_signature", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "signatureCount": repeatedCompletedSignatures.count
                ])
                currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    runId: runId,
                    repeatedSignatures: repeatedCompletedSignatures.sorted(),
                    availableTools: availableTools
                )
                continue
            }
            let repeatedFailedSignatures = currentToolCallSignatures.intersection(previouslyFailedToolCallSignatures)
            if !repeatedFailedSignatures.isEmpty {
                ToolExecutionTelemetry.shared.recordRepeatedToolCallSignatures(count: repeatedFailedSignatures.count)
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_failed_signature", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "signatureCount": repeatedFailedSignatures.count
                ])
                currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    runId: runId,
                    repeatedSignatures: repeatedFailedSignatures.sorted(),
                    availableTools: availableTools
                )
                continue
            }
            let repeatedSignatureCount = currentToolCallSignatures.intersection(previousToolCallSignatures).count
            if repeatedSignatureCount > 0 {
                ToolExecutionTelemetry.shared.recordRepeatedToolCallSignatures(count: repeatedSignatureCount)
            }
            let isFullyRepeatedSignatureBatch =
                !currentToolCallSignatures.isEmpty &&
                repeatedSignatureCount == currentToolCallSignatures.count
            previousToolCallSignatures = currentToolCallSignatures

            if isFullyRepeatedSignatureBatch {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_signature_batch", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "signatureCount": currentToolCallSignatures.count
                ])
                currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    runId: runId,
                    repeatedSignatures: currentToolCallSignatures.sorted(),
                    availableTools: availableTools
                )
                continue
            }

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
                let updateSignature = assistantUpdateSignature(
                    content: split.content,
                    reasoning: split.reasoning,
                    toolCalls: uniqueToolCalls
                )
                if updateSignature == previousAssistantUpdateSignature {
                    ToolExecutionTelemetry.shared.recordRepeatedAssistantUpdate()
                }
                historyCoordinator.append(assistantMsg)
                previousAssistantUpdateSignature = updateSignature
            }

            logAssistantToolCalls(
                conversationId: conversationId,
                content: split.content,
                toolCalls: uniqueToolCalls
            )

            markCancelledToolCalls(toolCalls: uniqueToolCalls, cancelledToolCallIds: cancelledToolCallIds())

            let statusSummary = buildGenericToolExecutionStatusSummary(
                toolCalls: uniqueToolCalls,
                iteration: toolIteration
            )
            if !hasModelStepUpdate && !hasReasoning {
                let statusSignature = assistantUpdateSignature(
                    content: statusSummary,
                    reasoning: nil,
                    toolCalls: uniqueToolCalls
                )
                if statusSignature == previousAssistantUpdateSignature {
                    ToolExecutionTelemetry.shared.recordRepeatedAssistantUpdate()
                }
                historyCoordinator.append(ChatMessage(
                    role: .assistant,
                    content: statusSummary
                ))
                previousAssistantUpdateSignature = statusSignature
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
            let failedToolCallIds = Set(toolResults.compactMap { result -> String? in
                guard result.isToolExecution, result.toolStatus == .failed else { return nil }
                return result.toolCallId
            })
            if !failedToolCallIds.isEmpty {
                let failedSignatures = uniqueToolCalls
                    .filter { failedToolCallIds.contains($0.id) }
                    .map(toolCallSignature)
                previouslyFailedToolCallSignatures.formUnion(failedSignatures)
            }
            let completedToolCallIds = Set(toolResults.compactMap { result -> String? in
                guard result.isToolExecution, result.toolStatus == .completed else { return nil }
                return result.toolCallId
            })
            if !completedToolCallIds.isEmpty {
                let completedSignatures = uniqueToolCalls
                    .filter { completedToolCallIds.contains($0.id) }
                    .map(toolCallSignature)
                previouslyCompletedToolCallSignatures.formUnion(completedSignatures)
            }
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
            let completionFeedbackMessage = toolCompletionFeedbackMessage(
                toolCalls: uniqueToolCalls,
                toolResults: toolResults
            )
            let toolLoopContext = toolLoopContextMessage(toolResults: toolResults)
            var followupMessages = historyCoordinator.messages
            
            if let toolLoopContext {
                followupMessages.append(toolLoopContext)
            }
            if let completionFeedbackMessage {
                followupMessages.append(completionFeedbackMessage)
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
        let failedToolCallSignatures: [String] = failedToolResults.compactMap { result in
            guard let toolCallId = result.toolCallId,
                  let toolCall = toolCallIndex[toolCallId] else {
                return nil
            }
            return toolCallSignature(toolCall)
        }
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

        if !failedToolCallSignatures.isEmpty {
            recoveryLines.append(contentsOf: [
                "",
                "Avoid retrying these exact failed call signatures:",
                failedToolCallSignatures.map { "- \($0)" }.joined(separator: "\n")
            ])
        }

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

    private func toolCompletionFeedbackMessage(
        toolCalls: [AIToolCall],
        toolResults: [ChatMessage]
    ) -> ChatMessage? {
        let completedToolResults = toolResults.filter {
            $0.isToolExecution && $0.toolStatus == .completed
        }
        guard !completedToolResults.isEmpty else { return nil }

        let toolCallIndex = Dictionary(uniqueKeysWithValues: toolCalls.map { ($0.id, $0) })
        let completedSignatures = completedToolResults.compactMap { result -> String? in
            guard let toolCallId = result.toolCallId,
                  let toolCall = toolCallIndex[toolCallId] else {
                return nil
            }
            return toolCallSignature(toolCall)
        }
        guard !completedSignatures.isEmpty else { return nil }

        return ChatMessage(
            role: .system,
            content: [
                "Tool calls completed successfully this iteration.",
                "Treat these call signatures as already completed work and avoid repeating them unless new evidence requires a changed call.",
                "Completed call signatures:",
                completedSignatures.map { "- \($0)" }.joined(separator: "\n")
            ].joined(separator: "\n")
        )
    }

    private func buildGenericToolExecutionStatusSummary(
        toolCalls: [AIToolCall],
        iteration: Int
    ) -> String {
        let callPreview = toolCalls.prefix(2).map { toolCall in
            let target = (toolCall.arguments["path"] as? String)
                ?? (toolCall.arguments["target_file"] as? String)
                ?? "project files"
            return "\(toolCall.name) on \(target)"
        }.joined(separator: "; ")

        let moreCount = max(0, toolCalls.count - 2)
        let suffix = moreCount > 0 ? " (+\(moreCount) more)" : ""
        return "Update (step \(iteration)): Prepared this execution step and now running \(callPreview)\(suffix) to move the implementation forward."
    }

    private func toolLoopStepUpdateInstructionMessage(consecutiveReadOnlyIterations: Int = 0) -> ChatMessage {
        let baseInstruction = PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/tool_loop_step_update_instruction",
            defaultValue: "Before returning tool calls, include either (a) a short <ide_reasoning> block with Analyze/Plan/Action bullets or (b) one short user-facing update sentence that states what was just completed and what you will do next (and how). Then return tool calls. Do not ask the user for additional input.",
            projectRoot: nil
        )
        var content = baseInstruction
        
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
            content: PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/plan_incomplete_continue",
                defaultValue: "The implementation plan is not complete yet. Continue with the next unfinished checklist item. Include a short reasoning/update, then return tool calls. Do not finish with a final answer yet.",
                projectRoot: projectRoot
            )
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

        var parts: [String] = [
            PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                defaultValue: "You are a coding assistant. Your job right now is to execute the task with tools. If helpful, include a concise <ide_reasoning> block before your update. RESPONSE FORMAT (required): 1) Optional: <ide_reasoning> with short Analyze/Plan/Action bullets only. 2) Then one short user-facing update sentence stating what you will do next and why. 3) Then return the tool calls needed for that step. Keep reasoning and update concise. Do not ask the user for input.",
                projectRoot: projectRoot
            )
        ]

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
                
                let executionPromptTemplate = PromptRepository.shared.prompt(
                    key: "ConversationFlow/Corrections/tool_loop_execution_transition",
                    defaultValue: "You have been gathering context with read-only tools but haven't made any changes yet. The user's request requires EXECUTION, not just exploration. You MUST now transition to execution: 1. Use write_files for multi-file scaffolding and coordinated creation 2. Use write_file only for single-file creation/overwrite 3. Use replace_in_file to modify existing files 4. Use run_command for build/test commands. Proceed with execution now using the available write/edit tools. User request:\n{{user_input}}\n\nContext gathered:\n{{tool_summary}}",
                    projectRoot: projectRoot
                )
                let executionPrompt = ChatMessage(
                    role: .system,
                    content: executionPromptTemplate
                        .replacingOccurrences(of: "{{user_input}}", with: userInput)
                        .replacingOccurrences(of: "{{tool_summary}}", with: toolSummary)
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
        let correctionTemplate = PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/tool_loop_stalled_final_response",
            defaultValue: "You kept calling tools without producing a user-visible response. Stop calling tools now and provide a final response in plain text.\n\nUser request:\n{{user_input}}\n\nTool outputs:\n{{tool_summary}}",
            projectRoot: projectRoot
        )
        let correctionSystem = ChatMessage(
            role: .system,
            content: correctionTemplate
                .replacingOccurrences(of: "{{user_input}}", with: userInput)
                .replacingOccurrences(of: "{{tool_summary}}", with: toolSummary)
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

    private func assistantUpdateSignature(
        content: String,
        reasoning: String?,
        toolCalls _: [AIToolCall]
    ) -> String {
        let normalizedContent = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedReasoning = (reasoning ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return [
            normalizedContent,
            normalizedReasoning
        ].joined(separator: "|#|")
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
        let correctionTemplate = PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/repeated_write_targets",
            defaultValue: "You are repeatedly writing the same target files without completing the user's request.\n\nRepeated write targets: {{write_targets}}\n\nDiversify execution now by progressing missing work and returning concrete tool calls.\n\nUser request:\n{{user_input}}",
            projectRoot: projectRoot
        )
        let correctionSystem = ChatMessage(
            role: .system,
            content: correctionTemplate
                .replacingOccurrences(of: "{{write_targets}}", with: writeTargetSignature)
                .replacingOccurrences(of: "{{user_input}}", with: userInput)
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

    private func requestDiversifiedExecutionForRepeatedSignatures(
        explicitContext: String?,
        projectRoot: URL,
        mode: AIMode,
        userInput: String,
        runId: String,
        repeatedSignatures: [String],
        availableTools: [AITool]
    ) async throws -> AIServiceResponse {
        let correctionTemplate = PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/repeated_tool_signatures",
            defaultValue: "You just repeated the exact same tool-call signatures from the prior iteration.\n\nRepeated signatures:\n{{repeated_signatures}}\n\nPivot to a different sequence that advances completion, or finish with a concise final answer if no more tools are needed.\n\nUser request:\n{{user_input}}",
            projectRoot: projectRoot
        )
        let correctionSystem = ChatMessage(
            role: .system,
            content: correctionTemplate
                .replacingOccurrences(of: "{{repeated_signatures}}", with: repeatedSignatures.map { "- \($0)" }.joined(separator: "\n"))
                .replacingOccurrences(of: "{{user_input}}", with: userInput)
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
