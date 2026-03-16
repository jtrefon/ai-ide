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
        var currentTurnTools = availableTools
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
        var repeatedCompletedSignatureCount = 0
        var hasObservedSuccessfulMutation = false
        var hasObservedSuccessfulDirectRead = false
        var mutatedArtifactPaths: Set<String> = []
        var hasObservedMutationVerificationRead = false
        var consecutivePostMutationNonMutationIterations = 0
        var consecutiveNonRecoverableMutationFailureIterations = 0
        let maxIterations = (mode == .agent) ? ToolLoopConstants.maxAgentIterations : ToolLoopConstants.maxNonAgentIterations

        if mode == .agent,
           currentResponse.toolCalls?.isEmpty ?? true,
           !availableTools.isEmpty,
           shouldForceInitialExecutionFollowup(
                userInput: userInput,
                response: currentResponse,
                projectRoot: projectRoot
           ) {
            await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.pre_loop", data: [
                "runId": runId,
                "hasToolCalls": false,
                "contentLength": currentResponse.content?.count ?? 0
            ])

            let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                userInput: userInput,
                conversationId: conversationId,
                projectRoot: projectRoot,
                historyMessages: historyCoordinator.messages
            )

            currentTurnTools = availableTools
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: focusedMessages,
                    explicitContext: explicitContext,
                    tools: currentTurnTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.tool_loop
                ))
                .get()
        }

        if mode == .agent,
           currentResponse.toolCalls?.isEmpty ?? true,
           !availableTools.isEmpty,
           let content = currentResponse.content,
           ChatPromptBuilder.shouldForceExecutionFollowup(
               userInput: userInput,
               content: content,
               hasToolCalls: false
           ) {
            let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                userInput: userInput,
                conversationId: conversationId,
                projectRoot: projectRoot,
                historyMessages: historyCoordinator.messages
            )
            currentTurnTools = availableTools
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: focusedMessages,
                    explicitContext: explicitContext,
                    tools: currentTurnTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.tool_loop,
                    conversationId: conversationId
                ))
                .get()
        }

        while let toolCalls = currentResponse.toolCalls,
              !toolCalls.isEmpty,
              toolIteration < maxIterations {
            toolIteration += 1
            let uniqueToolCalls = deduplicateToolCalls(toolCalls)
            lastToolCalls = uniqueToolCalls

            let unavailableToolNames = unavailableToolNames(
                for: uniqueToolCalls,
                availableTools: currentTurnTools
            )
            if !unavailableToolNames.isEmpty {
                if hasObservedSuccessfulMutation,
                   !hasOutstandingRequestedArtifacts(
                        userInput: userInput,
                        projectRoot: projectRoot
                   ),
                   allMutatedArtifactsExist(mutatedArtifactPaths),
                   unavailableToolNames.allSatisfy(isReadOnlyToolName),
                   !lastToolResults.contains(where: { $0.isToolExecution && $0.toolStatus == .failed }) {
                    currentResponse = try await requestFinalResponseForStalledToolLoop(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        toolResults: lastToolResults,
                        runId: runId,
                        availableTools: nil,
                        conversationId: conversationId,
                        hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
                    )
                    break
                }
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_unavailable_tool_recovery", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "toolNames": unavailableToolNames
                ])
                let recoveryTools: [AITool]
                if requestLikelyRequiresMutation(userInput), !hasObservedSuccessfulMutation {
                    recoveryTools = hasObservedSuccessfulDirectRead
                        ? strictMutationExecutionTools(from: availableTools)
                        : mutationRecoveryTools(from: availableTools)
                } else {
                    recoveryTools = currentTurnTools
                }
                currentTurnTools = recoveryTools
                currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    runId: runId,
                    repeatedSignatures: unavailableToolNames.map { "unavailable_tool:\($0)" },
                    availableTools: recoveryTools,
                    conversationId: conversationId
                )
                toolIteration = max(0, toolIteration - 1)
                continue
            }

            let currentToolBatchSignature = toolBatchSignature(uniqueToolCalls)
            let currentToolCallSignatures = Set(uniqueToolCalls.map(toolCallSignature))
            let repeatedCompletedSignatures = currentToolCallSignatures.intersection(previouslyCompletedToolCallSignatures)
            if !repeatedCompletedSignatures.isEmpty {
                repeatedCompletedSignatureCount += 1
                ToolExecutionTelemetry.shared.recordRepeatedToolCallSignatures(count: repeatedCompletedSignatures.count)
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_completed_signature", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "signatureCount": repeatedCompletedSignatures.count
                ])

                if repeatedCompletedSignatureCount >= ToolLoopConstants.repeatedCompletedSignatureStallThreshold {
                    await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_completed_signature_stall", data: [
                        "runId": runId,
                        "iteration": toolIteration,
                        "repeatedCount": repeatedCompletedSignatureCount
                    ])
                    if !hasObservedSuccessfulMutation,
                       requestLikelyRequiresMutation(userInput),
                       !currentTurnTools.isEmpty {
                        let diversifiedTools = hasObservedSuccessfulDirectRead
                            ? strictMutationExecutionTools(from: availableTools)
                            : mutationRecoveryTools(from: availableTools)
                        currentTurnTools = diversifiedTools
                        currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                            explicitContext: explicitContext,
                            projectRoot: projectRoot,
                            mode: mode,
                            userInput: userInput,
                            runId: runId,
                            repeatedSignatures: repeatedCompletedSignatures.sorted(),
                            availableTools: diversifiedTools,
                            conversationId: conversationId
                        )
                        repeatedCompletedSignatureCount = 0
                        continue
                    }

                    let finalizationTools: [AITool]? =
                        hasObservedSuccessfulMutation ? nil : currentTurnTools
                    currentResponse = try await requestFinalResponseForStalledToolLoop(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        toolResults: lastToolResults,
                        runId: runId,
                        availableTools: finalizationTools,
                        conversationId: conversationId
                    )
                    if finalizationTools != nil, shouldResumeRecoveredExecution(from: currentResponse) {
                        repeatedCompletedSignatureCount = 0
                        toolIteration = max(0, toolIteration - 1)
                        continue
                    }
                    break
                }

                currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    runId: runId,
                    repeatedSignatures: repeatedCompletedSignatures.sorted(),
                    availableTools: currentTurnTools,
                    conversationId: conversationId
                )
                continue
            }
            repeatedCompletedSignatureCount = 0
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
                    availableTools: currentTurnTools,
                    conversationId: conversationId
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

            if isFullyRepeatedSignatureBatch {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_repeated_signature_batch", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "signatureCount": currentToolCallSignatures.count
                ])
                let diversifiedTools: [AITool]
                if requestLikelyRequiresMutation(userInput), !hasObservedSuccessfulMutation {
                    diversifiedTools = hasObservedSuccessfulDirectRead
                        ? strictMutationExecutionTools(from: availableTools)
                        : mutationRecoveryTools(from: availableTools)
                } else {
                    diversifiedTools = availableTools
                }
                currentTurnTools = diversifiedTools
                currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    runId: runId,
                    repeatedSignatures: currentToolCallSignatures.sorted(),
                    availableTools: diversifiedTools,
                    conversationId: conversationId
                )
                continue
            }

            previousToolCallSignatures = currentToolCallSignatures

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
                    availableTools: currentTurnTools,
                    conversationId: conversationId
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
                if hasObservedSuccessfulMutation,
                   !hasOutstandingRequestedArtifacts(
                        userInput: userInput,
                        projectRoot: projectRoot
                   ),
                   hasObservedMutationVerificationRead,
                   !lastToolResults.contains(where: { $0.isToolExecution && $0.toolStatus == .failed }) {
                    currentResponse = try await requestFinalResponseForStalledToolLoop(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        toolResults: lastToolResults,
                        runId: runId,
                        availableTools: nil,
                        conversationId: conversationId,
                        hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
                    )
                    break
                }
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
                    availableTools: currentTurnTools,
                    conversationId: conversationId
                )
                if shouldResumeRecoveredExecution(from: currentResponse) {
                    toolIteration = max(0, toolIteration - 1)
                    continue
                }
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
            let normalizedProgress = normalizedProgressUpdate(
                modelContent: split.content,
                modelReasoning: split.reasoning,
                toolCalls: uniqueToolCalls,
                iteration: toolIteration
            )
            let hasModelStepUpdate = !normalizedProgress.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
            let hasReasoning = !(normalizedProgress.reasoning?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ?? true)
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: normalizedProgress.content,
                context: ChatMessageContentContext(reasoning: normalizedProgress.reasoning),
                billing: latestDraftAssistantBilling(),
                tool: ChatMessageToolContext(toolCalls: uniqueToolCalls)
            )
            if hasModelStepUpdate || hasReasoning {
                let updateSignature = assistantUpdateSignature(
                    content: normalizedProgress.content,
                    reasoning: normalizedProgress.reasoning,
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
                content: normalizedProgress.content,
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
                    content: statusSummary,
                    billing: latestDraftAssistantBilling()
                ))
                previousAssistantUpdateSignature = statusSignature
            }

            let toolResults = await toolExecutionCoordinator.executeToolCalls(
                uniqueToolCalls,
                availableTools: currentTurnTools,
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
                    if msg.toolStatus == ToolExecutionStatus.completed {
                        ToolExecutionTelemetry.shared.recordSuccessfulExecution()
                    }
                } else {
                    historyCoordinator.append(msg)
                }
            }

            lastToolResults = toolResults
            let failedToolCallIds = Set(toolResults.compactMap { result -> String? in
                guard result.isToolExecution, result.toolStatus == ToolExecutionStatus.failed else { return nil }
                return result.toolCallId
            })
            if !failedToolCallIds.isEmpty {
                let failedSignatures = uniqueToolCalls
                    .filter { failedToolCallIds.contains($0.id) }
                    .map(toolCallSignature)
                previouslyFailedToolCallSignatures.formUnion(failedSignatures)

                if requestLikelyRequiresMutation(userInput),
                   hasUnsupportedToolFailure(in: toolResults) {
                    if hasObservedSuccessfulMutation || hasReservedFilePathHint(in: toolResults) {
                        currentTurnTools = contentWriteRecoveryTools(from: availableTools)
                    } else {
                        currentTurnTools = hasObservedSuccessfulDirectRead
                            ? strictMutationExecutionTools(from: availableTools)
                            : mutationRecoveryTools(from: availableTools)
                    }
                    currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        runId: runId,
                        repeatedSignatures: failedSignatures,
                        availableTools: currentTurnTools,
                        conversationId: conversationId
                    )
                    continue
                }

                if requestLikelyRequiresMutation(userInput),
                   !hasObservedSuccessfulMutation,
                   !hasObservedSuccessfulDirectRead,
                   hasFailedDirectRead(in: toolResults) {
                    currentTurnTools = failedDirectReadRecoveryTools(from: availableTools)
                    currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        runId: runId,
                        repeatedSignatures: failedSignatures,
                        availableTools: currentTurnTools,
                        conversationId: conversationId
                    )
                    continue
                }

                if requestLikelyRequiresMutation(userInput),
                   hasCreateFileAlreadyExistsFailure(in: toolResults) {
                    currentTurnTools = contentWriteRecoveryTools(from: availableTools)
                    currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        runId: runId,
                        repeatedSignatures: failedSignatures,
                        availableTools: currentTurnTools,
                        conversationId: conversationId
                    )
                    continue
                }
            }
            let completedToolCallIds = Set(toolResults.compactMap { result -> String? in
                guard result.isToolExecution, result.toolStatus == ToolExecutionStatus.completed else { return nil }
                return result.toolCallId
            })
            if !completedToolCallIds.isEmpty {
                let completedSignatures = uniqueToolCalls
                    .filter { completedToolCallIds.contains($0.id) }
                    .map(toolCallSignature)
                previouslyCompletedToolCallSignatures.formUnion(completedSignatures)

                if uniqueToolCalls.contains(where: { toolCall in
                    completedToolCallIds.contains(toolCall.id) && isDirectReadToolName(toolCall.name)
                }) {
                    hasObservedSuccessfulDirectRead = true
                }
            }

            let successfulMutationThisIteration = uniqueToolCalls.contains { toolCall in
                completedToolCallIds.contains(toolCall.id) && isMutationToolName(toolCall.name)
            }
            let completedCreateFileReservationThisIteration = uniqueToolCalls.contains { toolCall in
                completedToolCallIds.contains(toolCall.id) && toolCall.name == "create_file"
            }
            let completedContentWriteThisIteration = uniqueToolCalls.contains { toolCall in
                completedToolCallIds.contains(toolCall.id) && isContentWritingToolName(toolCall.name)
            }
            if successfulMutationThisIteration {
                hasObservedSuccessfulMutation = true
                mutatedArtifactPaths.formUnion(completedMutationPaths(
                    toolCalls: uniqueToolCalls,
                    completedToolCallIds: completedToolCallIds,
                    projectRoot: projectRoot
                ))
                hasObservedMutationVerificationRead = false
                consecutivePostMutationNonMutationIterations = 0
            } else if hasObservedSuccessfulMutation {
                consecutivePostMutationNonMutationIterations += 1
            }
            if hasObservedSuccessfulMutation,
               completedReadVerificationHitMutatedArtifacts(
                    toolCalls: uniqueToolCalls,
                    completedToolCallIds: completedToolCallIds,
                    mutatedArtifactPaths: mutatedArtifactPaths,
                    projectRoot: projectRoot
               ) {
                hasObservedMutationVerificationRead = true
            }
            if shouldStopForNonRecoverableMutationFailureStall(
                toolResults: toolResults,
                successfulMutationThisIteration: successfulMutationThisIteration,
                consecutiveFailureIterations: &consecutiveNonRecoverableMutationFailureIterations
            ) {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_nonrecoverable_mutation_failure_stall", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "count": consecutiveNonRecoverableMutationFailureIterations
                ])
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: toolResults,
                    runId: runId,
                    availableTools: nil
                )
                break
            }
            if hasObservedSuccessfulMutation,
               consecutivePostMutationNonMutationIterations >= ToolLoopConstants.postWriteNonMutationStallThreshold {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_post_mutation_non_mutation_stall", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "count": consecutivePostMutationNonMutationIterations
                ])
                if hasOutstandingRequestedArtifacts(
                    userInput: userInput,
                    projectRoot: projectRoot
                ) {
                    currentTurnTools = contentWriteRecoveryTools(from: availableTools)
                    currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        runId: runId,
                        repeatedSignatures: ["post_mutation_non_mutation_stall"],
                        availableTools: currentTurnTools,
                        conversationId: conversationId
                    )
                    consecutivePostMutationNonMutationIterations = 0
                    continue
                }
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: toolResults,
                    runId: runId,
                    availableTools: nil
                )
                break
            }
            if hasObservedSuccessfulMutation,
               completedContentWriteThisIteration,
               !hasOutstandingRequestedArtifacts(
                    userInput: userInput,
                    projectRoot: projectRoot
               ),
               !toolResults.contains(where: { $0.isToolExecution && $0.toolStatus == .failed }) {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_requested_artifacts_completed", data: [
                    "runId": runId,
                    "iteration": toolIteration
                ])
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: toolResults,
                    runId: runId,
                    availableTools: nil,
                    conversationId: conversationId,
                    hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
                )
                break
            }
            await advancePlanProgressIfNeeded(
                conversationId: conversationId,
                successfulMutationThisIteration: successfulMutationThisIteration
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
            if shouldInjectStepUpdateInstruction(
                iteration: toolIteration,
                consecutiveReadOnlyIterations: consecutiveReadOnlyToolIterations,
                hasFailureRecovery: failureRecoveryMessage != nil
            ) {
                followupMessages.append(try toolLoopStepUpdateInstructionMessage(
                    projectRoot: projectRoot,
                    consecutiveReadOnlyIterations: consecutiveReadOnlyToolIterations
                ))
            }
            
            followupMessages = MessageTruncationPolicy.truncateForModel(followupMessages)

            let followupTools: [AITool]
            if requestLikelyRequiresMutation(userInput),
               hasOutstandingRequestedArtifacts(
                    userInput: userInput,
                    projectRoot: projectRoot
               ) {
                followupTools = hasObservedSuccessfulDirectRead || hasObservedSuccessfulMutation
                    ? contentWriteRecoveryTools(from: availableTools)
                    : mutationRecoveryTools(from: availableTools)
            } else if requestLikelyRequiresMutation(userInput),
               completedCreateFileReservationThisIteration,
               !completedContentWriteThisIteration {
                followupTools = contentWriteRecoveryTools(from: availableTools)
            } else if requestLikelyRequiresMutation(userInput),
                      hasObservedSuccessfulMutation,
                      (
                        isContentWriteRecoverySubset(currentTurnTools, availableTools: availableTools)
                        || hasReservedFilePathHint(in: toolResults)
                      ) {
                followupTools = contentWriteRecoveryTools(from: availableTools)
            } else if requestLikelyRequiresMutation(userInput),
               !hasObservedSuccessfulMutation,
               consecutiveReadOnlyToolIterations > 0 {
                followupTools = hasObservedSuccessfulDirectRead
                    ? strictMutationExecutionTools(from: availableTools)
                    : mutationRecoveryTools(from: availableTools)
            } else {
                followupTools = availableTools
            }

            currentTurnTools = followupTools
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: followupMessages,
                    explicitContext: explicitContext,
                    tools: currentTurnTools,
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
                if requestLikelyRequiresMutation(userInput),
                   !hasObservedSuccessfulMutation {
                    let recoveryTools = hasObservedSuccessfulDirectRead
                        ? strictMutationExecutionTools(from: availableTools)
                        : mutationRecoveryTools(from: availableTools)
                    currentTurnTools = recoveryTools
                    currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        runId: runId,
                        repeatedSignatures: ["repeated_no_tool_call_content"],
                        availableTools: recoveryTools,
                        conversationId: conversationId
                    )
                    repeatedNoToolCallContentCount = 0
                    continue
                }
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: lastToolResults,
                    runId: runId,
                    availableTools: nil
                )
                break
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               await shouldPreserveNoToolHandoffWithoutIncompletePlan(
                    content: content,
                    conversationId: conversationId
               ),
               !ChatPromptBuilder.shouldForceToolFollowup(content: content),
               !ChatPromptBuilder.shouldForceExecutionFollowup(
                    userInput: userInput,
                    content: content,
                    hasToolCalls: false
               ) {
                break
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               hasObservedSuccessfulMutation,
               !hasOutstandingRequestedArtifacts(
                    userInput: userInput,
                    projectRoot: projectRoot
               ),
               hasObservedMutationVerificationRead,
               !lastToolResults.contains(where: { $0.isToolExecution && $0.toolStatus == .failed }),
               !ChatPromptBuilder.containsTextualToolCallMarkup(content),
               !ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                    content: content,
                    projectRoot: projectRoot
               ) {
                break
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               hasObservedSuccessfulMutation,
               !hasOutstandingRequestedArtifacts(
                    userInput: userInput,
                    projectRoot: projectRoot
               ),
               isSyntheticProgressArtifact(content),
               !ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                    content: content,
                    projectRoot: projectRoot
               ) {
                break
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               hasObservedSuccessfulMutation,
               !hasOutstandingRequestedArtifacts(
                    userInput: userInput,
                    projectRoot: projectRoot
               ),
               (
                    ChatPromptBuilder.indicatesWorkWasPerformed(content: content)
                    || isSyntheticProgressArtifact(content)
               ),
               !ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                    content: content,
                    projectRoot: projectRoot
               ),
               !ChatPromptBuilder.shouldForceToolFollowup(content: content),
               !ChatPromptBuilder.shouldForceExecutionFollowup(
                    userInput: userInput,
                    content: content,
                    hasToolCalls: false
               ) {
                break
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               hasObservedSuccessfulMutation,
               isContentWriteRecoverySubset(currentTurnTools, availableTools: availableTools),
               !lastToolResults.contains(where: { $0.isToolExecution && $0.toolStatus == .failed }),
               ChatPromptBuilder.deliveryStatus(from: content) == .done,
               !ChatPromptBuilder.shouldForceToolFollowup(content: content),
               !ChatPromptBuilder.shouldForceExecutionFollowup(
                    userInput: userInput,
                    content: content,
                    hasToolCalls: false
               ) {
                break
            }

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               !(await shouldPreserveNoToolHandoffWithoutIncompletePlan(
                    content: content,
                    conversationId: conversationId
               )),
               (
                    ChatPromptBuilder.shouldForceToolFollowup(content: content)
                    || ChatPromptBuilder.shouldForceExecutionFollowup(
                        userInput: userInput,
                        content: content,
                        hasToolCalls: false
                    )
                    || ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                        content: content,
                        projectRoot: projectRoot
                    )
               ),
               !currentTurnTools.isEmpty {
                 if hasObservedSuccessfulMutation,
                    ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                    content: content,
                    projectRoot: projectRoot
                 ) {
                    currentResponse = try await requestFinalResponseForStalledToolLoop(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        toolResults: lastToolResults,
                        runId: runId,
                        availableTools: currentTurnTools,
                        conversationId: conversationId,
                        hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
                    )
                    if shouldResumeRecoveredExecution(from: currentResponse) {
                        toolIteration = max(0, toolIteration - 1)
                        continue
                    }
                 }

                 if isContentWriteRecoverySubset(currentTurnTools, availableTools: availableTools),
                    hasReservedFilePathHint(in: lastToolResults) {
                    currentResponse = try await requestFinalResponseForStalledToolLoop(
                        explicitContext: explicitContext,
                        projectRoot: projectRoot,
                        mode: mode,
                        userInput: userInput,
                        toolResults: lastToolResults,
                        runId: runId,
                        availableTools: currentTurnTools,
                        conversationId: conversationId,
                        hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
                    )
                    if shouldResumeRecoveredExecution(from: currentResponse) {
                        toolIteration = max(0, toolIteration - 1)
                        continue
                    }
                 }

                 await AIToolTraceLogger.shared.log(type: "chat.force_execution_followup.tool_loop", data: [
                     "runId": runId,
                     "iteration": toolIteration,
                     "hasToolCalls": false,
                     "contentLength": content.count
                 ])
                 let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                     userInput: userInput,
                     conversationId: conversationId,
                     projectRoot: projectRoot,
                     historyMessages: historyCoordinator.messages
                 )
                 currentResponse = try await aiInteractionCoordinator
                     .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                         messages: focusedMessages,
                         explicitContext: explicitContext,
                         tools: currentTurnTools,
                         mode: mode,
                         projectRoot: projectRoot,
                         runId: runId,
                         stage: AIRequestStage.tool_loop,
                         conversationId: conversationId
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
                        availableTools: currentTurnTools,
                        conversationId: conversationId
                    )
                    if shouldResumeRecoveredExecution(from: currentResponse) {
                        toolIteration = max(0, toolIteration - 1)
                        continue
                    }
                    break
                }
            }

             if mode == .agent,
                currentResponse.toolCalls?.isEmpty ?? true,
                let content = currentResponse.content,
                !(await shouldPreserveNoToolHandoffWithoutIncompletePlan(
                    content: content,
                    conversationId: conversationId
                )),
                ChatPromptBuilder.isRequestingUserInputForNextStep(content: content),
                !currentTurnTools.isEmpty {
                 let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                     userInput: userInput,
                     conversationId: conversationId,
                     projectRoot: projectRoot,
                     historyMessages: historyCoordinator.messages
                 )
                 currentResponse = try await aiInteractionCoordinator
                     .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                         messages: focusedMessages,
                         explicitContext: explicitContext,
                         tools: currentTurnTools,
                         mode: mode,
                         projectRoot: projectRoot,
                         runId: runId,
                         stage: AIRequestStage.tool_loop,
                         conversationId: conversationId
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
                        availableTools: currentTurnTools,
                        conversationId: conversationId
                    )
                    break
                }
            }

             if mode == .agent,
                currentResponse.toolCalls?.isEmpty ?? true,
                let content = currentResponse.content,
                !(await shouldPreserveNoToolHandoffWithoutIncompletePlan(
                    content: content,
                    conversationId: conversationId
                )),
                ChatPromptBuilder.isRequestingUserInputForNextStep(content: content),
                availableTools.isEmpty {
                 let autonomousMessages = try await ToolLoopUtilities.buildAutonomousNoUserInputMessages(
                     userInput: userInput,
                     conversationId: conversationId,
                     projectRoot: projectRoot,
                     existingAssistantContent: content,
                     toolsAvailable: false
                 )
                 currentTurnTools = availableTools
                 currentResponse = try await aiInteractionCoordinator
                     .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                         messages: autonomousMessages,
                         explicitContext: explicitContext,
                         tools: currentTurnTools,
                         mode: mode,
                         projectRoot: projectRoot,
                         runId: runId,
                         stage: AIRequestStage.tool_loop,
                         conversationId: conversationId
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
                        availableTools: availableTools,
                        conversationId: conversationId
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

        currentResponse = try await requestContinuationIfPlanIncompleteOrNeedsWork(
            currentResponse: currentResponse,
            explicitContext: explicitContext,
            mode: mode,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: currentTurnTools,
            runId: runId,
            userInput: userInput,
            hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
        )

        currentResponse = try await requestExecutionRecoveryIfPlanStillIncomplete(
            currentResponse: currentResponse,
            explicitContext: explicitContext,
            mode: mode,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: currentTurnTools,
            runId: runId,
            userInput: userInput,
            hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
        )

        if let escalatedContinuationResponse = try await requestEscalatedExecutionRecoveryForRecoveredReadOnlyToolCalls(
            currentResponse: currentResponse,
            explicitContext: explicitContext,
            mode: mode,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            runId: runId,
            userInput: userInput
        ) {
            currentResponse = escalatedContinuationResponse
        }

        if shouldResumeRecoveredExecution(from: currentResponse) {
            let recoveredToolLoopResult = try await handleToolLoopIfNeeded(
                response: currentResponse,
                explicitContext: explicitContext,
                mode: mode,
                projectRoot: projectRoot,
                conversationId: conversationId,
                availableTools: availableTools,
                cancelledToolCallIds: cancelledToolCallIds,
                runId: runId,
                userInput: userInput
            )

            return ToolLoopResult(
                response: recoveredToolLoopResult.response,
                lastToolCalls: recoveredToolLoopResult.lastToolCalls.isEmpty
                    ? lastToolCalls
                    : recoveredToolLoopResult.lastToolCalls,
                lastToolResults: lastToolResults + recoveredToolLoopResult.lastToolResults
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
            let envelope = ToolExecutionEnvelope.decode(from: result.content)
            var detailLines: [String] = [
                "- \(toolName) (\(toolCallId)): \(output) [\(argumentSummary)]"
            ]
            if let envelopeKeys = envelope?.argumentKeys, !envelopeKeys.isEmpty {
                detailLines.append("  normalized keys: \(envelopeKeys.joined(separator: ", "))")
            }
            if let invocation = envelope?.argumentPreview,
               !invocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailLines.append("  invocation: \(invocation)")
            }
            if let hint = envelope?.recoveryHint,
               !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailLines.append("  recovery_hint: \(hint)")
            }
            return detailLines.joined(separator: "\n")
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
                "If these completed calls satisfy the user request, provide the final response now without additional tool calls.",
                "Completed call signatures:",
                completedSignatures.map { "- \($0)" }.joined(separator: "\n")
            ].joined(separator: "\n")
        )
    }

    private func buildGenericToolExecutionStatusSummary(
        toolCalls: [AIToolCall],
        iteration: Int
    ) -> String {
        _ = toolCalls
        _ = iteration
        return ""
    }

    private func normalizedProgressUpdate(
        modelContent: String,
        modelReasoning: String?,
        toolCalls: [AIToolCall],
        iteration: Int
    ) -> (content: String, reasoning: String?) {
        _ = modelContent
        _ = modelReasoning
        _ = toolCalls
        _ = iteration
        return ("", nil)
    }

    private func progressTriplet(
        toolCalls: [AIToolCall],
        modelContent: String?,
        iteration: Int
    ) -> (what: String, how: String, wherePath: String) {
        let compactTargets = uniqueStringsPreservingOrder(toolCalls.compactMap(extractCompactTarget(from:)))
        let compactPathSummary = compactTargets.prefix(2).joined(separator: ", ")
        let wherePath = compactPathSummary.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
            ? "project files"
            : compactPathSummary

        let how = summarizeExecutionIntent(toolCalls: toolCalls)

        let what: String
        if let modelContent, let distilled = distilledWhat(from: modelContent) {
            what = distilled
        } else {
            what = "Completed progress update for step \(iteration)"
        }

        return (what, how, wherePath)
    }

    private func summarizeExecutionIntent(toolCalls: [AIToolCall]) -> String {
        guard !toolCalls.isEmpty else {
            return "continuing implementation"
        }

        let readOnlyTools: Set<String> = [
            "read_file",
            "index_read_file",
            "index_find_files",
            "index_list_files",
            "index_list_symbols",
            "index_search_text",
            "index_search_symbols",
            "index_list_memories",
            "checkpoint_list",
            "conversation_fold"
        ]
        let writeTools: Set<String> = [
            "write_file",
            "write_files",
            "replace_in_file",
            "create_file",
            "delete_file"
        ]
        let commandTools: Set<String> = ["run_command"]

        let names = Set(toolCalls.map { $0.name })
        let hasWrite = !names.intersection(writeTools).isEmpty
        let hasRunCommand = !names.intersection(commandTools).isEmpty
        let hasReadOnly = !names.intersection(readOnlyTools).isEmpty

        if hasWrite && hasRunCommand {
            return "applying code changes and validating results"
        }
        if hasWrite {
            return "applying targeted code changes"
        }
        if hasRunCommand {
            return "running validation commands"
        }
        if hasReadOnly {
            return "reviewing retrieved context and finalizing when the objective is satisfied"
        }
        return "executing the next implementation step"
    }

    private func uniqueStringsPreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func distilledWhat(from content: String) -> String? {
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        if cleaned.localizedCaseInsensitiveContains("update (step") {
            return nil
        }

        let noDuplicateNext: String
        if let range = cleaned.range(of: " Next:", options: [.caseInsensitive]) {
            noDuplicateNext = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            noDuplicateNext = cleaned
        }

        guard !noDuplicateNext.isEmpty else { return nil }
        return noDuplicateNext.count > 120
            ? String(noDuplicateNext.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
            : noDuplicateNext
    }

    private func extractCompactTarget(from toolCall: AIToolCall) -> String? {
        let keys = ["path", "target_file", "file", "file_path", "directory"]
        for key in keys {
            if let raw = toolCall.arguments[key] as? String,
               let compact = compactPath(raw) {
                return compact
            }
        }
        return nil
    }

    private func compactPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return parts[0] }

        if let srcIndex = parts.firstIndex(of: "src"), srcIndex < parts.count {
            return parts[srcIndex...].prefix(3).joined(separator: "/")
        }

        let penultimate = parts[parts.count - 2]
        if looksLikeEphemeralIdentifier(penultimate) {
            return parts.last
        }

        return parts.suffix(2).joined(separator: "/")
    }

    private func looksLikeEphemeralIdentifier(_ value: String) -> Bool {
        let lowercase = value.lowercased()
        return lowercase.count >= 16 && lowercase.contains("-")
    }

    private func toolLoopStepUpdateInstructionMessage(
        projectRoot: URL,
        consecutiveReadOnlyIterations: Int = 0
    ) throws -> ChatMessage {
        let baseInstruction = try PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/tool_loop_step_update_instruction",
            projectRoot: projectRoot
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

    private func shouldInjectStepUpdateInstruction(
        iteration: Int,
        consecutiveReadOnlyIterations: Int,
        hasFailureRecovery: Bool
    ) -> Bool {
        if hasFailureRecovery {
            return true
        }
        if consecutiveReadOnlyIterations >= ToolLoopConstants.readOnlyIterationNudgeThreshold {
            return true
        }
        if iteration == 1 {
            return true
        }
        return iteration % 4 == 0
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
        return text.contains("tool calls:")
            || text.contains("tool call:")
            || text.contains("<minimax:tool_call>")
            || text.contains("<invoke name=")
    }

    private func latestDraftAssistantBilling() -> ChatMessageBillingContext? {
        historyCoordinator.messages.reversed().first {
            $0.role == .assistant && $0.isDraft
        }?.billing
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
            "list_files",
            "read_file",
            "index_read_file",
            "index_find_files",
            "index_list_files",
            "index_list_symbols",
            "index_search_text",
            "index_search_symbols",
            "index_list_memories",
            "checkpoint_list",
            "conversation_fold"
        ]
    }

    private var mutationRecoveryToolNames: Set<String> {
        [
            "read_file",
            "write_file",
            "write_files",
            "create_file",
            "delete_file",
            "replace_in_file"
        ]
    }

    private var contentWriteRecoveryToolNames: Set<String> {
        [
            "read_file",
            "index_read_file",
            "create_file",
            "write_file",
            "write_files",
            "replace_in_file",
            "delete_file"
        ]
    }

    private var failedDirectReadRecoveryToolNames: Set<String> {
        [
            "list_files",
            "read_file",
            "write_file",
            "write_files",
            "create_file",
            "delete_file",
            "replace_in_file"
        ]
    }

    private var mutationOnlyToolNames: Set<String> {
        [
            "write_file",
            "write_files",
            "create_file",
            "delete_file",
            "replace_in_file"
        ]
    }

    private func mutationRecoveryTools(from availableTools: [AITool]) -> [AITool] {
        let preferredTools = availableTools.filter { mutationRecoveryToolNames.contains($0.name) }
        return preferredTools.isEmpty ? availableTools : preferredTools
    }

    private func failedDirectReadRecoveryTools(from availableTools: [AITool]) -> [AITool] {
        let preferredTools = availableTools.filter { failedDirectReadRecoveryToolNames.contains($0.name) }
        return preferredTools.isEmpty ? availableTools : preferredTools
    }

    private func mutationOnlyTools(from availableTools: [AITool]) -> [AITool] {
        let preferredTools = availableTools.filter { mutationOnlyToolNames.contains($0.name) }
        return preferredTools.isEmpty ? availableTools : preferredTools
    }

    private func strictMutationExecutionTools(from availableTools: [AITool]) -> [AITool] {
        let preferredTools = mutationOnlyTools(from: availableTools)
        if preferredTools.isEmpty {
            return availableTools.filter { !readOnlyLoopToolNames.contains($0.name) }
        }
        return preferredTools
    }

    private func unavailableToolNames(for toolCalls: [AIToolCall], availableTools: [AITool]) -> [String] {
        guard !toolCalls.isEmpty else { return [] }
        let availableToolNames = Set(availableTools.map(\.name))
        return Array(Set(toolCalls.compactMap { toolCall in
            if availableToolNames.contains(toolCall.name) {
                return nil
            }
            let aliases = toolNameAliases[toolCall.name] ?? []
            return aliases.contains(where: availableToolNames.contains) ? nil : toolCall.name
        })).sorted()
    }

    private func completedMutationPaths(
        toolCalls: [AIToolCall],
        completedToolCallIds: Set<String>,
        projectRoot: URL
    ) -> Set<String> {
        var paths: Set<String> = []
        for toolCall in toolCalls where completedToolCallIds.contains(toolCall.id) {
            switch toolCall.name {
            case "write_file", "create_file", "delete_file", "replace_in_file", "write_to_file":
                if let path = toolCall.arguments["path"] as? String {
                    paths.insert(normalizeToolPath(path, projectRoot: projectRoot))
                }
            case "write_files":
                if let files = toolCall.arguments["files"] as? [[String: Any]] {
                    for file in files {
                        if let path = file["path"] as? String {
                            paths.insert(normalizeToolPath(path, projectRoot: projectRoot))
                        }
                    }
                }
            default:
                continue
            }
        }
        return paths
    }

    private func completedReadVerificationHitMutatedArtifacts(
        toolCalls: [AIToolCall],
        completedToolCallIds: Set<String>,
        mutatedArtifactPaths: Set<String>,
        projectRoot: URL
    ) -> Bool {
        guard !mutatedArtifactPaths.isEmpty else { return false }
        for toolCall in toolCalls where completedToolCallIds.contains(toolCall.id) {
            guard toolCall.name == "read_file" || toolCall.name == "index_read_file" else {
                continue
            }
            guard let path = toolCall.arguments["path"] as? String else { continue }
            let normalizedPath = normalizeToolPath(path, projectRoot: projectRoot)
            if mutatedArtifactPaths.contains(normalizedPath) {
                return true
            }
        }
        return false
    }

    private func allMutatedArtifactsExist(_ mutatedArtifactPaths: Set<String>) -> Bool {
        guard !mutatedArtifactPaths.isEmpty else { return false }
        let fileManager = FileManager.default
        return mutatedArtifactPaths.allSatisfy { fileManager.fileExists(atPath: $0) }
    }

    private func hasOutstandingRequestedArtifacts(userInput: String, projectRoot: URL) -> Bool {
        let explicitArtifacts = requestedExplicitArtifacts(from: userInput, projectRoot: projectRoot)
        if explicitArtifacts.contains(where: { !FileManager.default.fileExists(atPath: $0) }) {
            return true
        }

        let sourceArtifacts = explicitArtifacts.filter(isLikelySourceArtifactPath)
        guard requestSuggestsTestCoverage(userInput), !sourceArtifacts.isEmpty else {
            return false
        }

        for sourceArtifact in sourceArtifacts {
            let candidates = inferredTestArtifactCandidates(for: sourceArtifact, projectRoot: projectRoot)
            guard !candidates.isEmpty else { continue }
            if !candidates.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
                return true
            }
        }

        return false
    }

    private func requestedExplicitArtifacts(from userInput: String, projectRoot: URL) -> Set<String> {
        let pattern = #"(?<![A-Za-z0-9_./-])([A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8})(?![A-Za-z0-9_./-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(userInput.startIndex..<userInput.endIndex, in: userInput)
        var results: Set<String> = []

        for match in regex.matches(in: userInput, options: [], range: range) {
            guard let tokenRange = Range(match.range(at: 1), in: userInput) else { continue }
            let rawToken = String(userInput[tokenRange])
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[](){}<>.,;:"))
            guard !token.isEmpty else { continue }
            results.insert(normalizeToolPath(token, projectRoot: projectRoot))
        }

        return results
    }

    private func requestSuggestsTestCoverage(_ userInput: String) -> Bool {
        let normalized = userInput.lowercased()
        let coverageSignals = [
            "test",
            "tests",
            "spec",
            "coverage",
            "unit test",
            "unit tests"
        ]
        return coverageSignals.contains(where: { normalized.contains($0) })
    }

    private func isLikelySourceArtifactPath(_ path: String) -> Bool {
        let normalized = path.lowercased()
        guard normalized.contains("/src/") || normalized.hasPrefix("src/") else {
            return false
        }
        return normalized.hasSuffix(".js")
            || normalized.hasSuffix(".jsx")
            || normalized.hasSuffix(".ts")
            || normalized.hasSuffix(".tsx")
            || normalized.hasSuffix(".swift")
            || normalized.hasSuffix(".py")
    }

    private func inferredTestArtifactCandidates(for sourceArtifact: String, projectRoot: URL) -> Set<String> {
        let sourceURL = URL(fileURLWithPath: sourceArtifact)
        let ext = sourceURL.pathExtension
        guard !ext.isEmpty else { return [] }

        let fileStem = sourceURL.deletingPathExtension().lastPathComponent
        let sourceDir = sourceURL.deletingLastPathComponent()
        let projectPath = projectRoot.standardizedFileURL.path
        let relativeSourceDir = sourceDir.path.hasPrefix(projectPath)
            ? String(sourceDir.path.dropFirst(projectPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : sourceDir.lastPathComponent

        let baseNames = [
            "\(fileStem).test.\(ext)",
            "\(fileStem).spec.\(ext)"
        ]

        var candidates: Set<String> = []
        for baseName in baseNames {
            candidates.insert(projectRoot.appendingPathComponent("tests/\(baseName)").standardizedFileURL.path)
            candidates.insert(sourceDir.appendingPathComponent(baseName).standardizedFileURL.path)
            candidates.insert(sourceDir.appendingPathComponent("__tests__/\(baseName)").standardizedFileURL.path)
            if !relativeSourceDir.isEmpty {
                candidates.insert(projectRoot.appendingPathComponent("tests/\(relativeSourceDir)/\(baseName)").standardizedFileURL.path)
            }
        }

        return candidates
    }

    private func isReadOnlyToolName(_ toolName: String) -> Bool {
        readOnlyLoopToolNames.contains(toolName)
            || toolName == "list_files"
            || toolName == "read_file"
            || toolName == "index_read_file"
    }

    private func normalizeToolPath(_ path: String, projectRoot: URL) -> String {
        let candidateURL: URL
        if path.hasPrefix("/") {
            candidateURL = URL(fileURLWithPath: path)
        } else {
            candidateURL = projectRoot.appendingPathComponent(path)
        }
        return candidateURL.standardizedFileURL.path
    }

    private var toolNameAliases: [String: [String]] {
        [
            "find_by_name": ["find_file", "index_find_files"],
            "find": ["find_by_name"],
            "grep_search": ["grep", "index_search_text"],
            "grep": ["grep_search"],
            "list_dir": ["list_files", "index_list_files", "list_all_files"],
            "list_directory": ["list_files", "index_list_files", "list_all_files"],
            "get_project_structure": ["list_all_files", "list_files"],
            "read": ["read_file"],
            "view_file": ["read_file", "index_read_file"],
            "write": ["write_file", "write_files"],
            "write_files": ["write_file"],
            "write_to_file": ["write_file", "write_files"],
            "create_file": ["write_file", "write_files"],
            "edit_file": ["replace_in_file", "write_file"],
            "apply_patch": ["replace_in_file", "write_file"],
            "cli-mcp-server_run_command": ["run_command"],
            "run_terminal_command": ["run_command"],
            "run_shell_command": ["run_command"]
        ]
    }

    private func contentWriteRecoveryTools(from availableTools: [AITool]) -> [AITool] {
        let preferredTools = availableTools.filter { contentWriteRecoveryToolNames.contains($0.name) }
        return preferredTools.isEmpty ? availableTools : preferredTools
    }

    private func advancePlanProgressIfNeeded(
        conversationId: String,
        successfulMutationThisIteration: Bool
    ) async {
        guard successfulMutationThisIteration else { return }

        guard let currentPlan = await ConversationPlanStore.shared.get(conversationId: conversationId),
              !currentPlan.isEmpty,
              let updatedPlan = PlanChecklistTracker.markNextPendingItemCompleted(in: currentPlan) else {
            return
        }

        await ConversationPlanStore.shared.set(conversationId: conversationId, plan: updatedPlan)
    }

    private func shouldStopForNonRecoverableMutationFailureStall(
        toolResults: [ChatMessage],
        successfulMutationThisIteration: Bool,
        consecutiveFailureIterations: inout Int
    ) -> Bool {
        guard !successfulMutationThisIteration else {
            consecutiveFailureIterations = 0
            return false
        }

        let nonRecoverableMutationFailures = toolResults.filter { result in
            guard result.isToolExecution,
                  result.toolStatus == .failed,
                  let toolName = result.toolName,
                  isMutationToolName(toolName) else {
                return false
            }

            let output = ToolLoopUtilities.toolOutputText(from: result).lowercased()
            return output.contains("malformed arguments for")
                || output.contains("pre-write prevention blocked tool")
                || output.contains("duplicate_impl")
        }

        guard !nonRecoverableMutationFailures.isEmpty else {
            consecutiveFailureIterations = 0
            return false
        }

        consecutiveFailureIterations += 1
        return consecutiveFailureIterations >= 2
    }

    private func hasUnsupportedToolFailure(in toolResults: [ChatMessage]) -> Bool {
        toolResults.contains { result in
            guard result.isToolExecution, result.toolStatus == .failed else {
                return false
            }

            return ToolLoopUtilities.toolOutputText(from: result)
                .localizedCaseInsensitiveContains("tool not found in current turn")
        }
    }

    private func hasFailedDirectRead(in toolResults: [ChatMessage]) -> Bool {
        toolResults.contains { result in
            guard result.isToolExecution,
                  result.toolStatus == .failed,
                  result.toolName == "read_file" else {
                return false
            }

            let output = ToolLoopUtilities.toolOutputText(from: result).lowercased()
            return output.contains("file not found")
                || output.contains("no such file")
                || output.contains("couldn’t be opened")
                || output.contains("could not be opened")
        }
    }

    private func hasCreateFileAlreadyExistsFailure(in toolResults: [ChatMessage]) -> Bool {
        toolResults.contains { result in
            guard result.isToolExecution,
                  result.toolStatus == .failed,
                  result.toolName == "create_file" else {
                return false
            }

            return ToolLoopUtilities.toolOutputText(from: result)
                .localizedCaseInsensitiveContains("already exists")
        }
    }

    private func isContentWritingToolName(_ toolName: String) -> Bool {
        switch toolName {
        case "write_file", "write_files", "replace_in_file":
            return true
        default:
            return false
        }
    }

    private func isContentWriteRecoverySubset(_ currentTools: [AITool], availableTools: [AITool]) -> Bool {
        let currentToolNames = Set(currentTools.map(\.name))
        let contentWriteToolNames = Set(contentWriteRecoveryTools(from: availableTools).map(\.name))
        return !currentToolNames.isEmpty && currentToolNames == contentWriteToolNames
    }

    private func hasReservedFilePathHint(in toolResults: [ChatMessage]) -> Bool {
        toolResults.contains { result in
            guard result.isToolExecution else { return false }

            let output = ToolLoopUtilities.toolOutputText(from: result)
            return output.localizedCaseInsensitiveContains("reserved file path at")
                || output.localizedCaseInsensitiveContains("file already exists at")
        }
    }

    private func requestFinalResponseForStalledToolLoop(
        explicitContext: String?,
        projectRoot: URL,
        mode: AIMode,
        userInput: String,
        toolResults: [ChatMessage],
        runId: String,
        availableTools: [AITool]? = nil,
        conversationId: String? = nil,
        hasObservedSuccessfulMutation: Bool = false
    ) async throws -> AIServiceResponse {
        let toolSummary = ToolLoopUtilities.toolResultsSummaryText(toolResults)

        // If we have execution tools available, try to force execution transition first
        if let availableTools, mode == .agent, let conversationId {
            let executionTools: [AITool]
            let availableToolNames = Set(availableTools.map(\.name))
            if !availableToolNames.isEmpty,
               availableToolNames.isSubset(of: contentWriteRecoveryToolNames) {
                executionTools = availableTools
            } else {
                executionTools = availableTools.filter { !readOnlyLoopToolNames.contains($0.name) }
            }

            if !executionTools.isEmpty {
                // Log the execution transition attempt
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_execution_transition", data: [
                    "runId": runId,
                    "executionToolsCount": executionTools.count,
                    "toolSummaryLength": toolSummary.count
                ])

                let executionMessages = try await ToolLoopUtilities.buildStalledExecutionTransitionMessages(
                    userInput: userInput,
                    conversationId: conversationId,
                    projectRoot: projectRoot,
                    toolSummary: toolSummary
                )

                let executionResponse = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: executionMessages,
                        explicitContext: explicitContext,
                        tools: executionTools,
                        mode: mode,
                        projectRoot: projectRoot,
                        runId: runId,
                        stage: AIRequestStage.tool_loop,
                        conversationId: conversationId
                    ))
                    .get()

                if let toolCalls = executionResponse.toolCalls, !toolCalls.isEmpty {
                    let hasExecutionTool = toolCalls.contains { !readOnlyLoopToolNames.contains($0.name) }
                    if hasExecutionTool {
                        return executionResponse
                    }
                }

                if let focusedRecoveryResponse = try await requestFocusedExecutionRecoveryIfPlanIncomplete(
                    currentResponse: executionResponse,
                    explicitContext: explicitContext,
                    mode: mode,
                    projectRoot: projectRoot,
                    conversationId: conversationId,
                    availableTools: availableTools,
                    runId: runId,
                    userInput: userInput,
                    hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
                ), shouldResumeRecoveredExecution(from: focusedRecoveryResponse) {
                    return focusedRecoveryResponse
                }
            }
        }

        // Fallback: request final response without tools
        let finalResponseMessages = try ToolLoopUtilities.buildStalledFinalResponseMessages(
            userInput: userInput,
            toolSummary: toolSummary,
            projectRoot: projectRoot
        )

        let followupMode: AIMode = (mode == .agent) ? .agent : .chat
        let followup = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: finalResponseMessages,
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

    private func shouldPreserveNoToolHandoffWithoutIncompletePlan(
        content: String,
        conversationId: String
    ) async -> Bool {
        guard isPureContinuationOrRecoverySummary(content) else { return false }

        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total > 0 else { return true }
        return planProgress.isComplete
    }

    private func isSyntheticProgressArtifact(_ content: String) -> Bool {
        let normalized = ChatPromptBuilder.contentForDisplay(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        if normalized.contains("next: reviewing retrieved context and finalizing when the objective is satisfied") {
            return true
        }

        let generatedPrefixes = [
            "done -> next -> path:",
            "done → next → path:",
            "completed progress update for step ",
            "start checkpoint scan.",
            "checking checkpoints pass "
        ]
        return generatedPrefixes.contains { normalized.hasPrefix($0) }
    }

    private func requestFocusedExecutionRecoveryIfPlanIncomplete(
        currentResponse: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String,
        hasObservedSuccessfulMutation: Bool
    ) async throws -> AIServiceResponse? {
        let recoveredResponse = try await requestExecutionRecoveryIfPlanStillIncomplete(
            currentResponse: currentResponse,
            explicitContext: explicitContext,
            mode: mode,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            runId: runId,
            userInput: userInput,
            hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
        )

        guard recoveredResponse.toolCalls?.isEmpty == false else {
            let recoveredContent = recoveredResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !recoveredContent.isEmpty,
               (isPureContinuationOrRecoverySummary(recoveredContent)
                || ChatPromptBuilder.deliveryStatus(from: recoveredContent) == .needsWork) {
                return recoveredResponse
            }
            return nil
        }

        if shouldEscalateRecoveredReadOnlyToolCalls(recoveredResponse) {
            return try await requestEscalatedExecutionRecoveryForRecoveredReadOnlyToolCalls(
                currentResponse: recoveredResponse,
                explicitContext: explicitContext,
                mode: mode,
                projectRoot: projectRoot,
                conversationId: conversationId,
                availableTools: availableTools,
                runId: runId,
                userInput: userInput
            ) ?? recoveredResponse
        }

        return recoveredResponse
    }

    private func requestEscalatedExecutionRecoveryForRecoveredReadOnlyToolCalls(
        currentResponse: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse? {
        guard shouldEscalateRecoveredReadOnlyToolCalls(currentResponse) else {
            return nil
        }

        let executionTools = strictMutationExecutionTools(from: availableTools)
        guard !executionTools.isEmpty else {
            return nil
        }

        let recoveredToolCalls = deduplicateToolCalls(currentResponse.toolCalls ?? [])
        let escalatedRecoveryResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
            explicitContext: explicitContext,
            projectRoot: projectRoot,
            mode: mode,
            userInput: userInput,
            runId: runId,
            repeatedSignatures: recoveredToolCalls.map(toolCallSignature),
            availableTools: executionTools,
            conversationId: conversationId
        )

        return escalatedRecoveryResponse
    }

    private func deduplicateToolCalls(_ toolCalls: [AIToolCall]) -> [AIToolCall] {
        var seenSignatures: Set<String> = []
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
        availableTools: [AITool],
        conversationId: String
    ) async throws -> AIServiceResponse {
        let correctionMessages = try await ToolLoopUtilities.buildRepeatedWriteTargetDiversionMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot,
            writeTargetSignature: writeTargetSignature
        )

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: correctionMessages,
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop,
                conversationId: conversationId
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
        availableTools: [AITool],
        conversationId: String
    ) async throws -> AIServiceResponse {
        let correctionMessages = try await ToolLoopUtilities.buildRepeatedSignatureDiversionMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot,
            repeatedSignatures: repeatedSignatures,
            historyMessages: historyCoordinator.messages,
            availableTools: availableTools
        )

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: correctionMessages,
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop,
                conversationId: conversationId
            ))
            .get()
    }

    private func requestContinuationIfPlanIncompleteOrNeedsWork(
        currentResponse: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String,
        hasObservedSuccessfulMutation: Bool
    ) async throws -> AIServiceResponse {
        guard mode == .agent else { return currentResponse }
        guard currentResponse.toolCalls?.isEmpty ?? true else { return currentResponse }
        guard !availableTools.isEmpty else { return currentResponse }

        let currentContent = currentResponse.content ?? ""
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        let hasSatisfiedClaimedArtifacts = hasObservedSuccessfulMutation
            && ChatPromptBuilder.indicatesWorkWasPerformed(content: currentContent)
            && !ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                content: currentContent,
                projectRoot: projectRoot
            )

        let shouldContinueForPlan = planProgress.total > 0 && !planProgress.isComplete
        guard shouldContinueForPlan else { return currentResponse }
        guard !hasSatisfiedClaimedArtifacts else { return currentResponse }

        let followupMessages = try await ToolLoopUtilities.buildPlanContinuationMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot,
            historyMessages: historyCoordinator.messages,
            currentAssistantContent: currentContent,
            planMarkdown: planMarkdown,
            completedCount: planProgress.completed,
            totalCount: planProgress.total
        )

        await AIToolTraceLogger.shared.log(type: "chat.tool_loop_continuation_recovery", data: [
            "runId": runId,
            "planProgress": "\(planProgress.completed)/\(planProgress.total)",
            "userInputLength": userInput.count
        ])

        let continuationTools: [AITool]
        if requestLikelyRequiresMutation(userInput), !hasObservedSuccessfulMutation {
            continuationTools = strictMutationExecutionTools(from: availableTools)
        } else {
            continuationTools = availableTools
        }

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: followupMessages,
                explicitContext: explicitContext,
                tools: continuationTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop,
                conversationId: conversationId
            ))
            .get()
    }

    private func requestExecutionRecoveryIfPlanStillIncomplete(
        currentResponse: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String,
        hasObservedSuccessfulMutation: Bool
    ) async throws -> AIServiceResponse {
        guard mode == .agent else { return currentResponse }
        guard currentResponse.toolCalls?.isEmpty ?? true else { return currentResponse }
        guard !availableTools.isEmpty else { return currentResponse }

        let currentContent = currentResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total > 0, !planProgress.isComplete else { return currentResponse }

        let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: currentContent)
        let deliveryStatusLabel: String
        switch deliveryStatus {
        case .done:
            deliveryStatusLabel = "done"
        case .needsWork:
            deliveryStatusLabel = "needs_work"
        case .none:
            deliveryStatusLabel = "missing"
        }
        let shouldRecoverExecution = deliveryStatus != .done
            || ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: userInput,
                content: currentContent,
                hasToolCalls: false
            )
            || ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                content: currentContent,
                projectRoot: projectRoot
            )
            || (requestLikelyRequiresMutation(userInput) && !hasObservedSuccessfulMutation)

        guard shouldRecoverExecution else { return currentResponse }

        await AIToolTraceLogger.shared.log(type: "chat.tool_loop_post_continuation_execution_recovery", data: [
            "runId": runId,
            "planProgress": "\(planProgress.completed)/\(planProgress.total)",
            "deliveryStatus": deliveryStatusLabel,
            "contentLength": currentContent.count
        ])

        let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot,
            historyMessages: historyCoordinator.messages
        )

        let recoveryTools: [AITool]
        if requestLikelyRequiresMutation(userInput), !hasObservedSuccessfulMutation {
            recoveryTools = strictMutationExecutionTools(from: availableTools)
        } else {
            recoveryTools = availableTools
        }

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: focusedMessages,
                explicitContext: explicitContext,
                tools: recoveryTools,
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.tool_loop,
                conversationId: conversationId
            ))
            .get()
    }

    private func shouldResumeRecoveredExecution(from response: AIServiceResponse) -> Bool {
        guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
            return false
        }

        return toolCalls.contains { !readOnlyLoopToolNames.contains($0.name) }
    }

    private func shouldEscalateRecoveredReadOnlyToolCalls(_ response: AIServiceResponse) -> Bool {
        guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
            return false
        }

        return toolCalls.allSatisfy { readOnlyLoopToolNames.contains($0.name) }
    }

    private func requestLikelyRequiresMutation(_ userInput: String) -> Bool {
        let normalized = userInput.lowercased()
        let mutationSignals = [
            "create ",
            "write ",
            "edit ",
            "modify ",
            "update ",
            "refactor ",
            "migrate ",
            "add ",
            "delete ",
            "remove ",
            "rename ",
            "implement "
        ]
        return mutationSignals.contains { normalized.contains($0) }
    }

    private func shouldForceInitialExecutionFollowup(
        userInput: String,
        response: AIServiceResponse,
        projectRoot: URL
    ) -> Bool {
        guard let content = response.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return true
        }

        if ChatPromptBuilder.containsTextualToolCallMarkup(content) {
            return true
        }

        if ChatPromptBuilder.indicatesWorkWasPerformed(content: content),
           !hasOutstandingRequestedArtifacts(
                userInput: userInput,
                projectRoot: projectRoot
           ),
           !ChatPromptBuilder.hasMissingClaimedFileArtifacts(
                content: content,
                projectRoot: projectRoot
           ),
           !ChatPromptBuilder.shouldForceToolFollowup(content: content),
           !ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: userInput,
                content: content,
                hasToolCalls: false
           ) {
            return false
        }

        return ChatPromptBuilder.shouldForceExecutionFollowup(
            userInput: userInput,
            content: content,
            hasToolCalls: false
        ) || requestLikelyRequiresMutation(userInput)
    }

    private func isPureContinuationOrRecoverySummary(_ content: String) -> Bool {
        let normalized = ChatPromptBuilder.contentForDisplay(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let recoverySignals = [
            "done -> next -> path:",
            "continue with remaining",
            "continuing with the next",
            "all checklist items are complete",
            "completed all requested implementation steps",
            "next i will",
            "next step:",
            "proceeding with",
            "moving on to"
        ]
        return recoverySignals.contains { normalized.hasPrefix($0) }
        || normalized.contains("next step is to")
    }

    private func isMutationToolName(_ toolName: String) -> Bool {
        switch toolName {
        case "write_file", "write_files", "create_file", "delete_file", "replace_in_file", "multi_replace_file_content", "write_to_file":
            return true
        default:
            return false
        }
    }

    private func isDirectReadToolName(_ toolName: String) -> Bool {
        switch toolName {
        case "read_file", "index_read_file":
            return true
        default:
            return false
        }
    }
}
