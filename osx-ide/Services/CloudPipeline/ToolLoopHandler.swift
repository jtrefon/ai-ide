import Foundation

@MainActor
final class ToolLoopHandler {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    var clearStreamingBuffer: (@MainActor () -> Void)?

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        toolExecutionCoordinator: ToolExecutionCoordinator,
        clearStreamingBuffer: (@MainActor () -> Void)? = nil
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
        self.toolExecutionCoordinator = toolExecutionCoordinator
        self.clearStreamingBuffer = clearStreamingBuffer
    }

    private static let maxRecursionDepth = 3

    func handleToolLoopIfNeeded(
        response: AIServiceResponse,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        cancelledToolCallIds: @escaping () -> Set<String>,
        runId: String,
        userInput: String,
        usesLocalModel: Bool = false,
        alreadyStalled: Bool = false,
        recursionDepth: Int = 0
    ) async throws -> ToolLoopResult {
        guard mode.isAgentic else {
            return ToolLoopResult(response: response, lastToolCalls: [], lastToolResults: [])
        }

        var currentResponse = response
        var currentTurnTools = availableTools

        // Surface tool calls whose arguments failed to parse as failed tool
        // results so the model can self-correct instead of the engine dispatching
        // a call with corrupted/missing arguments.
        if let malformed = response.malformedToolCalls, !malformed.isEmpty {
            await handleMalformedToolCalls(malformed, runId: runId, conversationId: conversationId)
        }

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
        /// Within a single tool loop, cache completed read-only results by their
        /// tool-call signature. Re-reading an identical file is wasted work and
        /// feeds the repeated-signature stall; reuse the prior result instead.
        var readResultCache: [String: ChatMessage] = [:]
        var previouslyFailedToolCallSignatures: Set<String> = []
        var previouslyCompletedToolCallSignatures: Set<String> = []
        var repeatedCompletedSignatureCount = 0
        var reachedStall = alreadyStalled
        var hasObservedSuccessfulMutation = false
        var hasObservedSuccessfulDirectRead = false
        var mutatedArtifactPaths: Set<String> = []
        var hasObservedMutationVerificationRead = false
        var consecutivePostMutationNonMutationIterations = 0
        var consecutiveNonRecoverableMutationFailureIterations = 0
        var lastContinuationRecoveryIteration = -10  // cooldown: 3 iterations between recoveries
        var lastNudgedPlanTask: String? = nil        // tracks plan task nudge to avoid spam
        var hasNudgedResearchPhase = false           // tracks research-phase nudge to avoid spam
        /// Convergence tracking (Context Access Layer, RC6)
        let loopStartTime = Date()
        var consecutiveReadsSinceLastSuccessfulMutation = 0

        let maxIterations = if usesLocalModel {
            ToolLoopConstants.maxMLXIterations
        } else if mode.isAgentic {
            ToolLoopConstants.maxAgentIterations
        } else {
            ToolLoopConstants.maxNonAgentIterations
        }

        if (mode.isAgentic),
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
                historyMessages: historyCoordinator.requestMessages
            )

            currentTurnTools = availableTools
            clearStreamingBuffer?()
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: focusedMessages,
                    tools: currentTurnTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.tool_loop
                ))
                .get()
        }

        if (mode.isAgentic),
           currentResponse.toolCalls?.isEmpty ?? true,
           !availableTools.isEmpty,
           let content = currentResponse.content {

            let split = ChatPromptBuilder.splitReasoning(from: content)
            let visibleContent = split.content.trimmingCharacters(in: .whitespacesAndNewlines)

            if visibleContent.isEmpty {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_empty_visible_content_recovery", data: [
                    "runId": runId,
                    "contentLength": content.count,
                    "hasReasoning": split.reasoning != nil
                ])
                let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                    userInput: userInput,
                    conversationId: conversationId,
                    projectRoot: projectRoot,
                    historyMessages: historyCoordinator.requestMessages
                )
                let correctionPrompt: String
                do {
                    correctionPrompt = try PromptRepository.shared.prompt(
                        key: "ConversationFlow/Corrections/empty_response_correction",
                        projectRoot: projectRoot
                    )
                } catch {
                    correctionPrompt = "Your previous response contained only reasoning with no visible output. Provide a direct response or use tools."
                }
                currentTurnTools = availableTools
                clearStreamingBuffer?()
                currentResponse = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: focusedMessages + [ChatMessage(role: .system, content: correctionPrompt)],
                        tools: currentTurnTools,
                        mode: mode,
                        projectRoot: projectRoot,
                        runId: runId,
                        stage: AIRequestStage.tool_loop,
                        conversationId: conversationId
                    ))
                    .get()
            }

            let updatedContent = currentResponse.content ?? content
            let forceToolFollowup = ChatPromptBuilder.shouldForceToolFollowup(content: updatedContent)
            let forceExecutionFollowup = ChatPromptBuilder.shouldForceExecutionFollowup(
               userInput: userInput,
               content: updatedContent,
               hasToolCalls: false
            )
            
            var shouldRecover = false
            if forceToolFollowup {
                // If it output textual tool calls, we ALWAYS want to recover to get proper JSON
                shouldRecover = true
            } else if forceExecutionFollowup {
                let planStore = ConversationPlanStore.shared
                if let planMarkdown = await planStore.get(conversationId: conversationId) {
                   let progress = PlanChecklistTracker.progress(in: planMarkdown)
                   if progress.total > 0 { // Trust AI if a plan checklist exists
                        shouldRecover = true
                   }
                }
            }

            if shouldRecover {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_needs_work_recovery_pre", data: [
                    "runId": runId
                ])
                
                let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                    userInput: userInput,
                    conversationId: conversationId,
                    projectRoot: projectRoot,
                    historyMessages: historyCoordinator.requestMessages
                )
                currentTurnTools = availableTools
                clearStreamingBuffer?()
                currentResponse = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: focusedMessages,
                        tools: currentTurnTools,
                        mode: mode,
                        projectRoot: projectRoot,
                        runId: runId,
                        stage: AIRequestStage.tool_loop,
                        conversationId: conversationId
                    ))
                    .get()
            }
        }

        while let toolCalls = currentResponse.toolCalls,
              !toolCalls.isEmpty,
              toolIteration < maxIterations {
            // Honor a user-initiated stop (ConversationManager.stopGeneration
            // cancels the enclosing Task). Throws CancellationError, which the
            // send coordinator's catch handles as a clean "Generation cancelled".
            try Task.checkCancellation()
            toolIteration += 1
            clearStreamingBuffer?()
            let uniqueToolCalls = deduplicateToolCalls(toolCalls)
            lastToolCalls = uniqueToolCalls
            if hasObservedSuccessfulMutation,
               !hasOutstandingRequestedArtifacts(
                    userInput: userInput,
                    projectRoot: projectRoot
               ),
               uniqueToolCalls.allSatisfy({ isMutationToolName($0.name) }),
               !lastToolResults.contains(where: { $0.isToolExecution && $0.toolStatus == .failed }) {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_post_mutation_write_stall", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "toolNames": uniqueToolCalls.map(\.name)
                ])
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                    "writeTargetSignature": currentWriteTargetSignature ?? "none",
                    "hasObservedSuccessfulMutation": hasObservedSuccessfulMutation
                ])

                if hasObservedSuccessfulMutation,
                   !hasOutstandingRequestedArtifacts(
                        userInput: userInput,
                        projectRoot: projectRoot
                   ),
                   !lastToolResults.contains(where: { $0.isToolExecution && $0.toolStatus == .failed }) {
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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

                currentResponse = try await requestDiversifiedExecutionForRepeatedWriteTargets(
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: lastToolResults,
                    runId: runId,
                    availableTools: nil // No tools - skip execution transition for repeated batch
                )
                break
            }
            
            // Convergence stall (RC6): wall-clock budget
            if Date().timeIntervalSince(loopStartTime) > ToolLoopConstants.maxToolLoopDuration {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_convergence_stall_time", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "duration": Date().timeIntervalSince(loopStartTime)
                ])
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
            
            // Convergence stall (RC6): reads without any successful mutation
            if consecutiveReadsSinceLastSuccessfulMutation > ToolLoopConstants.maxReadsWithoutMutation {
                await AIToolTraceLogger.shared.log(type: "chat.tool_loop_convergence_stall_reads", data: [
                    "runId": runId,
                    "iteration": toolIteration,
                    "consecutiveReadsSinceLastSuccessfulMutation": consecutiveReadsSinceLastSuccessfulMutation
                ])
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
            let effectiveReasoning = currentResponse.reasoning ?? split.reasoning
            let hasModelStepUpdate = !split.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
            let hasReasoning = !(effectiveReasoning?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ?? true)
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: effectiveReasoning),
                billing: latestDraftAssistantBilling(),
                tool: ChatMessageToolContext(toolCalls: uniqueToolCalls)
            )
            if hasModelStepUpdate || hasReasoning {
                let updateSignature = assistantUpdateSignature(
                    content: split.content,
                    reasoning: effectiveReasoning,
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

            if !hasModelStepUpdate && !hasReasoning {
                let statusSignature = assistantUpdateSignature(
                    content: "",
                    reasoning: nil,
                    toolCalls: uniqueToolCalls
                )
                if statusSignature == previousAssistantUpdateSignature {
                    ToolExecutionTelemetry.shared.recordRepeatedAssistantUpdate()
                }
                historyCoordinator.append(ChatMessage(
                    role: .assistant,
                    content: "",
                    billing: latestDraftAssistantBilling(),
                    tool: ChatMessageToolContext(toolCalls: uniqueToolCalls)
                ))
                previousAssistantUpdateSignature = statusSignature
            }

            // Reuse cached results for read-only calls repeated within this loop
            // (e.g. the model re-reading the same file), and only execute the rest.
            var cachedResults: [ChatMessage] = []
            var toExecute: [AIToolCall] = []
            for call in uniqueToolCalls {
                if readOnlyLoopToolNames.contains(call.name),
                   let cached = readResultCache[toolCallSignature(call)] {
                    cachedResults.append(cached)
                } else {
                    toExecute.append(call)
                }
            }

            let executedResults = await toolExecutionCoordinator.executeToolCalls(
                toExecute,
                availableTools: currentTurnTools,
                conversationId: conversationId
            ) { [weak self] progressMsg in
                guard let self else { return }
                if progressMsg.isToolExecution {
                    if progressMsg.toolStatus == .executing {
                        self.historyCoordinator.setLiveToolMessage(progressMsg)
                    } else {
                        self.historyCoordinator.clearLiveToolMessage(progressMsg.toolCallId ?? "")
                        self.historyCoordinator.commitToolResult(progressMsg)
                    }
                } else {
                    self.historyCoordinator.append(progressMsg)
                }
            }

            // Populate the cache with completed read-only results for reuse.
            for msg in executedResults where msg.isToolExecution && msg.toolStatus == .completed {
                if let call = toExecute.first(where: { $0.id == msg.toolCallId }),
                   readOnlyLoopToolNames.contains(call.name) {
                    readResultCache[toolCallSignature(call)] = msg
                }
            }

            let toolResults = cachedResults + executedResults

            for msg in toolResults {
                if msg.isToolExecution {
                    if msg.toolStatus == .executing {
                        historyCoordinator.setLiveToolMessage(msg)
                    } else {
                        historyCoordinator.clearLiveToolMessage(msg.toolCallId ?? "")
                        historyCoordinator.commitToolResult(msg)
                        if msg.toolStatus == ToolExecutionStatus.completed {
                            ToolExecutionTelemetry.shared.recordSuccessfulExecution()
                        }
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
            // Convergence tracking (RC6): reset on successful mutation, increment when all-read-only
            if successfulMutationThisIteration {
                consecutiveReadsSinceLastSuccessfulMutation = 0
            } else if uniqueToolCalls.allSatisfy({ MutationTools.readOnlyNames.contains($0.name) }) {
                consecutiveReadsSinceLastSuccessfulMutation += 1
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
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                // Check if a structured plan is active — if so, the plan governs completion
                let planStillActive = await ConversationPlanStore.shared.getPlan(conversationId: conversationId).map { !$0.isComplete } ?? false
                if !planStillActive {
                    await AIToolTraceLogger.shared.log(type: "chat.tool_loop_requested_artifacts_completed", data: [
                    "runId": runId,
                    "iteration": toolIteration
                ])
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
            let toolLoopContext = toolLoopContextMessage(toolResults: toolResults)
            var followupMessages = historyCoordinator.requestMessages
            
            if let toolLoopContext {
                followupMessages.append(toolLoopContext)
            }
            // Single follow-up message per turn (priority chain):
            // failure > step-update(read-only stall) > completion > plan > research
            if let failureRecoveryMessage {
                followupMessages.append(failureRecoveryMessage)
            } else if shouldInjectStepUpdateInstruction(
                iteration: toolIteration,
                consecutiveReadOnlyIterations: consecutiveReadOnlyToolIterations,
                hasFailureRecovery: failureRecoveryMessage != nil
            ) {
                followupMessages.append(try toolLoopStepUpdateInstructionMessage(
                    projectRoot: projectRoot,
                    consecutiveReadOnlyIterations: consecutiveReadOnlyToolIterations
                ))
            } else if let completionFeedbackMessage = toolCompletionFeedbackMessage(
                toolCalls: uniqueToolCalls,
                toolResults: toolResults
            ) {
                followupMessages.append(completionFeedbackMessage)
            } else if let planNudge = await planExecutionNudgeMessage(
                conversationId: conversationId,
                successfulMutationThisIteration: successfulMutationThisIteration,
                toolCalls: uniqueToolCalls,
                lastNudgedPlanTask: &lastNudgedPlanTask
            ) {
                followupMessages.append(planNudge)
            } else if let researchNudge = await planResearchNudgeMessage(
                conversationId: conversationId,
                toolCalls: uniqueToolCalls,
                hasNudged: &hasNudgedResearchPhase
            ) {
                followupMessages.append(researchNudge)
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
            clearStreamingBuffer?()
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: followupMessages,
                    tools: currentTurnTools,
                    mode: mode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.tool_loop,
                    conversationId: conversationId
                ))
                .get()

            // Special case: if the AI follow-up (currentResponse) produced no tool calls but indicated 
            // unfinished execution (NEEDS_WORK), and we have an incomplete plan, attempt a focused recovery.
            let followUpContent = currentResponse.content ?? ""
            if (currentResponse.toolCalls?.isEmpty ?? true) &&
               ChatPromptBuilder.shouldForceExecutionFollowup(userInput: userInput, content: followUpContent, hasToolCalls: false) &&
               consecutiveEmptyToolCallResponses < 1 {
                
                let planStore = ConversationPlanStore.shared
                if let planMarkdown = await planStore.get(conversationId: conversationId) {
                    let progress = PlanChecklistTracker.progress(in: planMarkdown)
                    if progress.total > 0 { // Trust AI if a plan checklist exists
                        await AIToolTraceLogger.shared.log(type: "chat.tool_loop_needs_work_recovery", data: [
                            "runId": runId,
                            "iteration": toolIteration
                        ])
                        
                        consecutiveEmptyToolCallResponses += 1
                        let focusedMessages = try await ToolLoopUtilities.buildFocusedExecutionMessages(
                            userInput: userInput,
                            conversationId: conversationId,
                            projectRoot: projectRoot,
                            historyMessages: historyCoordinator.requestMessages
                        )
                        
                        currentTurnTools = availableTools
                        clearStreamingBuffer?()
                        currentResponse = try await aiInteractionCoordinator
                            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                                messages: focusedMessages,
                                tools: availableTools,
                                mode: mode,
                                projectRoot: projectRoot,
                                runId: runId,
                                stage: AIRequestStage.tool_loop,
                                conversationId: conversationId
                            ))
                            .get()
        }
    }
}

            if !(currentResponse.toolCalls?.isEmpty ?? true) {
                consecutiveEmptyToolCallResponses = 0
            }

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
                let hasTextualPattern = ToolLoopUtilities.containsLiteralToolCallMarkup(currentResponse.content)
                ToolExecutionTelemetry.shared.recordResponseWithoutToolCalls(hasTextualPattern: hasTextualPattern)
                if requestLikelyRequiresMutation(userInput),
                   !hasObservedSuccessfulMutation {
                    let recoveryTools = hasObservedSuccessfulDirectRead
                        ? strictMutationExecutionTools(from: availableTools)
                        : mutationRecoveryTools(from: availableTools)
                    currentTurnTools = recoveryTools
                    currentResponse = try await requestDiversifiedExecutionForRepeatedSignatures(
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
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    projectRoot: projectRoot,
                    mode: mode,
                    userInput: userInput,
                    toolResults: lastToolResults,
                    runId: runId,
                    availableTools: nil
                )
                break
            }

            if mode.isAgentic,
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

            if mode.isAgentic,
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

            if mode.isAgentic,
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

            if mode.isAgentic,
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

            if mode.isAgentic,
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

            if mode.isAgentic,
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                     historyMessages: historyCoordinator.requestMessages
                 )
                 currentResponse = try await aiInteractionCoordinator
                     .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                         messages: focusedMessages,
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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

             if mode.isAgentic,
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
                     historyMessages: historyCoordinator.requestMessages
                 )
                 currentResponse = try await aiInteractionCoordinator
                     .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                         messages: focusedMessages,
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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

             if mode.isAgentic,
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
                     toolsAvailable: false,
                     historyMessages: historyCoordinator.requestMessages
                 )
                 currentTurnTools = availableTools
                 currentResponse = try await aiInteractionCoordinator
                     .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                         messages: autonomousMessages,
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
                    reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
                reachedStall = true
                currentResponse = try await requestFinalResponseForStalledToolLoop(
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
            mode: mode,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: currentTurnTools,
            runId: runId,
            userInput: userInput,
            hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
        )

        if toolIteration - lastContinuationRecoveryIteration >= 3 {
            lastContinuationRecoveryIteration = toolIteration
            currentResponse = try await requestExecutionRecoveryIfPlanStillIncomplete(
                currentResponse: currentResponse,
                mode: mode,
                projectRoot: projectRoot,
                conversationId: conversationId,
                availableTools: currentTurnTools,
                runId: runId,
                userInput: userInput,
                hasObservedSuccessfulMutation: hasObservedSuccessfulMutation
            )
        }
        if let escalatedContinuationResponse = try await requestEscalatedExecutionRecoveryForRecoveredReadOnlyToolCalls(
            currentResponse: currentResponse,
            mode: mode,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            runId: runId,
            userInput: userInput
        ) {
            currentResponse = escalatedContinuationResponse
        }

        if shouldResumeRecoveredExecution(from: currentResponse),
           recursionDepth < Self.maxRecursionDepth,
           !reachedStall,
           !(hasObservedSuccessfulMutation && !hasOutstandingRequestedArtifacts(
                userInput: userInput,
                projectRoot: projectRoot
           )) {
            let recoveredToolLoopResult = try await handleToolLoopIfNeeded(
                response: currentResponse,
                mode: mode,
                projectRoot: projectRoot,
                conversationId: conversationId,
                availableTools: availableTools,
                cancelledToolCallIds: cancelledToolCallIds,
                runId: runId,
                userInput: userInput,
                usesLocalModel: usesLocalModel,
                alreadyStalled: reachedStall,
                recursionDepth: recursionDepth + 1
            )

            return ToolLoopResult(
                response: recoveredToolLoopResult.response,
                lastToolCalls: recoveredToolLoopResult.lastToolCalls.isEmpty
                    ? lastToolCalls
                    : recoveredToolLoopResult.lastToolCalls,
                lastToolResults: lastToolResults + recoveredToolLoopResult.lastToolResults
            )
        }

        if hasObservedSuccessfulMutation,
           !hasOutstandingRequestedArtifacts(
                userInput: userInput,
                projectRoot: projectRoot
           ),
           currentResponse.toolCalls != nil {
            currentResponse = AIServiceResponse(
                content: currentResponse.content,
                toolCalls: nil,
                reasoning: currentResponse.reasoning
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
            historyCoordinator.cancelLiveTool(
                toolCallId: call.id,
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

    private func planExecutionNudgeMessage(
        conversationId: String,
        successfulMutationThisIteration: Bool,
        toolCalls: [AIToolCall],
        lastNudgedPlanTask: inout String?
    ) async -> ChatMessage? {
        guard successfulMutationThisIteration else { return nil }
        guard let plan = await ConversationPlanStore.shared.getPlan(conversationId: conversationId),
              !plan.isComplete,
              let activeItem = plan.activeItem else { return nil }
        let calledFinishTaskThisIteration = toolCalls.contains { call in
            call.name == "plan" && (call.arguments["action"] as? String) == "finishTask"
        }
        if calledFinishTaskThisIteration { return nil }
        if lastNudgedPlanTask == activeItem.id { return nil }
        lastNudgedPlanTask = activeItem.id
        return ChatMessage(
            role: .system,
            content: "[Plan] You are executing a plan. When the current task is complete, call `plan(action: \"finishTask\", summary: \"...\")` to save your summary and advance to the next task."
        )
    }

    private func planResearchNudgeMessage(
        conversationId: String,
        toolCalls: [AIToolCall],
        hasNudged: inout Bool
    ) async -> ChatMessage? {
        guard let plan = await ConversationPlanStore.shared.getPlan(conversationId: conversationId),
              plan.items.isEmpty else { return nil }
        let calledFinishTaskThisIteration = toolCalls.contains { call in
            call.name == "plan" && (call.arguments["action"] as? String) == "finishTask"
        }
        if calledFinishTaskThisIteration { return nil }
        if hasNudged { return nil }
        hasNudged = true
        return ChatMessage(
            role: .system,
            content: "[Plan] You are in the research phase. Use tools to explore the codebase and understand the current state. When you have a clear picture, call `plan(action: \"finishTask\", summary: \"...\")` with your proposed task breakdown. Do not start coding yet."
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
                "If the task requires changes to files, transition to execution now using write, edit, or bash. " +
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
        return consecutiveReadOnlyIterations >= ToolLoopConstants.readOnlyIterationNudgeThreshold
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

        if ToolLoopUtilities.containsLiteralToolCallMarkup(response.content) {
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
        MutationTools.readOnlyNames
    }

    private var mutationRecoveryToolNames: Set<String> {
        Set(["read"]).union(MutationTools.mutationNames)
    }

    private var contentWriteRecoveryToolNames: Set<String> {
        MutationTools.contentWriteNames
    }

    private var failedDirectReadRecoveryToolNames: Set<String> {
        MutationTools.readOnlyNames.union(MutationTools.mutationNames)
    }

    private var mutationOnlyToolNames: Set<String> {
        MutationTools.mutationNames
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
            return availableTools.filter { !MutationTools.isReadOnly($0.name) }
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
            let canonical = ToolAliasRegistry.shared.canonicalName(for: toolCall.name)
            return canonical != toolCall.name.lowercased() && availableToolNames.contains(canonical) ? nil : toolCall.name
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

    private func hasOutstandingRequestedArtifacts(userInput: String, projectRoot: URL, planIncomplete: Bool = false) -> Bool {
        // When a structured plan is active, the plan governs completion — not file-level artifact checks.
        if planIncomplete {
            return true
        }

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

    private func contentWriteRecoveryTools(from availableTools: [AITool]) -> [AITool] {
        let preferredTools = availableTools.filter { contentWriteRecoveryToolNames.contains($0.name) }
        return preferredTools.isEmpty ? availableTools : preferredTools
    }

    private func advancePlanProgressIfNeeded(
        conversationId: String,
        successfulMutationThisIteration: Bool
    ) async {
        guard successfulMutationThisIteration else { return }

        // If a structured TaskPlan exists, the new PlanTool handles advancement
        if await ConversationPlanStore.shared.getPlan(conversationId: conversationId) != nil {
            return
        }

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
        if let availableTools, mode.isAgentic, let conversationId {
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
                    toolSummary: toolSummary,
                    historyMessages: historyCoordinator.requestMessages
                )

                // An empty/error execution-transition response must not abort the
                // whole run. Degrade gracefully to the deterministic finalization
                // fallback below instead of throwing.
                let executionResponse: AIServiceResponse
                do {
                    executionResponse = try await aiInteractionCoordinator
                        .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                            messages: executionMessages,
                            tools: executionTools,
                            mode: mode,
                            projectRoot: projectRoot,
                            runId: runId,
                            stage: AIRequestStage.tool_loop,
                            conversationId: conversationId
                        ))
                        .get()
                } catch {
                    await AIToolTraceLogger.shared.log(type: "chat.tool_loop_finalization_fallback", data: [
                        "runId": runId,
                        "reason": "execution_transition_failed",
                        "error": "\(error)"
                    ])
                    return AIServiceResponse(
                        content: deterministicSummary(from: toolResults),
                        toolCalls: nil
                    )
                }

                if let toolCalls = executionResponse.toolCalls, !toolCalls.isEmpty {
                    let hasExecutionTool = toolCalls.contains { !readOnlyLoopToolNames.contains($0.name) }
                    if hasExecutionTool {
                        return executionResponse
                    }
                }

                if let focusedRecoveryResponse = try await requestFocusedExecutionRecoveryIfPlanIncomplete(
                    currentResponse: executionResponse,
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
            projectRoot: projectRoot,
            historyMessages: historyCoordinator.requestMessages
        )

        let followupMode: AIMode = mode
        // Guard against the finalization request throwing (e.g. the model
        // returns an empty response and retries are exhausted). Without this,
        // the whole run fails with no answer. Degrade to the deterministic
        // summary instead.
        let followup: AIServiceResponse
        do {
            followup = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: finalResponseMessages,
                    tools: [],
                    mode: followupMode,
                    projectRoot: projectRoot,
                    runId: runId,
                    stage: AIRequestStage.final_response
                ))
                .get()
        } catch {
            await AIToolTraceLogger.shared.log(type: "chat.tool_loop_finalization_fallback", data: [
                "runId": runId,
                "reason": "final_response_failed",
                "error": "\(error)"
            ])
            return AIServiceResponse(
                content: deterministicSummary(from: toolResults),
                toolCalls: nil
            )
        }

        let split = ChatPromptBuilder.splitReasoning(from: followup.content ?? "")
        let visibleContent = split.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent: String
        if !visibleContent.isEmpty, !ChatPromptBuilder.containsTextualToolCallMarkup(visibleContent) {
            finalContent = split.content
        } else if let reasoning = split.reasoning,
                  !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !ChatPromptBuilder.containsTextualToolCallMarkup(reasoning) {
            finalContent = reasoning
        } else {
            // The model returned nothing usable (or only textual tool-call markup
            // such as a malformed `<tool_call ...>` block). Guarantee a non-empty,
            // grounded answer derived from the tool activity instead of ending the
            // run silently or delivering garbage. This is a safety net, not the
            // primary path.
            finalContent = deterministicSummary(from: toolResults)
        }
        return AIServiceResponse(content: finalContent, toolCalls: nil)
    }

    /// Builds a non-LLM summary of tool activity so a stalled/empty finalization
    /// still yields a grounded answer to the user.
    private func deterministicSummary(from toolResults: [ChatMessage]) -> String {
        let summary = ToolLoopUtilities.toolResultsSummaryText(toolResults)
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "I gathered context using tools but the final summary could not be generated. Please retry."
        }
        return "Summary of tool activity:\n\(summary)"
    }

    // MARK: - Malformed Tool Calls

    /// Converts tool calls whose arguments failed to parse into failed tool
    /// results in history, so the model sees a real error and can re-issue the
    /// call with valid arguments. This is the primary recovery for the
    /// streaming argument-corruption defect (no `_raw_args_chunk` is ever dispatched).
    private func handleMalformedToolCalls(_ malformed: [MalformedToolCall], runId: String, conversationId: String) async {
        for call in malformed {
            await AIToolTraceLogger.shared.log(type: "chat.tool_call_malformed", data: [
                "runId": runId,
                "conversationId": conversationId,
                "toolCallId": call.id,
                "tool": call.name,
                "error": call.error,
                "rawArguments": call.rawArguments
            ])

            let message = ChatMessage(
                role: .tool,
                content: "Tool call \"\(call.name)\" had malformed arguments and could not be executed: \(call.error). Raw arguments: \(call.rawArguments). Please re-issue the tool call with valid JSON arguments.",
                tool: ChatMessageToolContext(
                    toolName: call.name,
                    toolStatus: .failed,
                    target: ToolInvocationTarget(targetFile: nil, toolCallId: call.id)
                )
            )
            historyCoordinator.append(message)
        }
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
            writeTargetSignature: writeTargetSignature,
            historyMessages: historyCoordinator.requestMessages
        )

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: correctionMessages,
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
            historyMessages: historyCoordinator.requestMessages,
            availableTools: availableTools
        )

        return try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: correctionMessages,
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
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String,
        hasObservedSuccessfulMutation: Bool
    ) async throws -> AIServiceResponse {
        guard mode.isAgentic else { return currentResponse }
        guard currentResponse.toolCalls?.isEmpty ?? true else { return currentResponse }
        guard !availableTools.isEmpty else { return currentResponse }

        if hasObservedSuccessfulMutation,
           !hasOutstandingRequestedArtifacts(
                userInput: userInput,
                projectRoot: projectRoot
           ) {
            return currentResponse
        }

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
            historyMessages: historyCoordinator.requestMessages,
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
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        runId: String,
        userInput: String,
        hasObservedSuccessfulMutation: Bool
    ) async throws -> AIServiceResponse {
        guard mode.isAgentic else { return currentResponse }
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
            deliveryStatusLabel = "done"  // No delivery info = assume done. The Kilo Code / non-OpenRouter models
                                          // don't emit structured Delivery: sections. Treat absent delivery
                                          // as complete unless other signals force a followup.
        }
        let shouldRecoverExecution = deliveryStatus == .needsWork  // Only recover on explicit needs_work
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
            historyMessages: historyCoordinator.requestMessages
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

// MARK: - Context Access Layer: Loop Break Controller & Follow-Up Assembler

/// Encapsulates the per-turn decision of whether the tool loop should continue,
/// stop (model signaled done), or force-stop (convergence stall / time budget).
/// Testable in isolation with canned TurnState values.
@MainActor
struct LoopBreakController {
    struct TurnState {
        let iteration: Int
        let hasSuccessfulMutation: Bool
        let toolCalls: [AIToolCall]
        let toolResults: [ChatMessage]
        let modelContent: String?
        let planStatus: PlanStatus
        let elapsed: TimeInterval
        let consecutiveReadsSinceLastMutation: Int
        let maxIterations: Int
    }

    struct PlanStatus {
        let hasPlan: Bool
        let hasChecklist: Bool
        let totalTasks: Int
        let completedTasks: Int
        let isComplete: Bool
    }

    enum Decision: Equatable, Sendable {
        case `continue`
        case stop
        case forceStop(reason: String)
    }

    static func decide(_ state: TurnState) -> Decision {
        // 1. Wall-clock budget (RC6)
        if state.elapsed > ToolLoopConstants.maxToolLoopDuration {
            return .forceStop(reason: "Time budget exceeded")
        }
        // 2. Reads without mutation (RC6)
        if state.consecutiveReadsSinceLastMutation > ToolLoopConstants.maxReadsWithoutMutation {
            return .forceStop(reason: "\(state.consecutiveReadsSinceLastMutation) consecutive read-only iterations without mutation")
        }
        // 3. Iteration cap
        if state.iteration >= state.maxIterations {
            return .forceStop(reason: "Iteration budget (\(state.maxIterations)) exhausted")
        }

        guard let content = state.modelContent, !content.isEmpty else {
            // Empty content with no tool calls → stop; with tool calls → continue
            return state.toolCalls.isEmpty ? .stop : .continue
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. Model signaled done
        if state.toolCalls.isEmpty {
            // If work was performed, trust the model's completion
            if ChatPromptBuilder.indicatesWorkWasPerformed(content: trimmed) {
                return .stop
            }
            // Completion signals → done
            let completionSignals = ["done", "completed", "finished", "all set", "resolved"]
            let lower = trimmed.lowercased()
            if completionSignals.contains(where: { lower.contains($0) }) {
                return .stop
            }
            // Pending execution signals with no tool calls → still force a continuation
            let pendingSignals = ["i will", "i'll", "i am going to", "i'm going to",
                                  "next i will", "now i will", "let me", "i can",
                                  "next:", "next →", "→ next:", "path:"]
            if pendingSignals.contains(where: { lower.contains($0) }) {
                return .continue
            }
            return .stop
        }

        return .continue
    }
}

/// Assembles the single follow-up message based on the LoopBreakController's decision.
/// Guarantees exactly one instruction per turn — never contradictory.
enum FollowUpMessageAssembler {
    static func assemble(
        decision: LoopBreakController.Decision,
        state: LoopBreakController.TurnState,
        projectRoot: URL,
        toolResults: [ChatMessage]
    ) -> ChatMessage? {
        switch decision {
        case .continue:
            let completedSignatures = toolResults
                .filter { $0.isToolExecution && $0.toolStatus == .completed }
                .compactMap { result -> String? in
                    guard let toolCallId = result.toolCallId else { return nil }
                    return StallDetector.toolCallSignature(
                        AIToolCall(id: toolCallId, name: result.toolName ?? "", arguments: ["": ""])
                    )
                }
            if completedSignatures.isEmpty {
                return ChatMessage(
                    role: .system,
                    content: "Continue with the next step."
                )
            }
            return ChatMessage(
                role: .system,
                content: [
                    "Tool calls completed successfully this iteration.",
                    "If these completed calls satisfy the user request, provide the final response now without additional tool calls.",
                    "Completed call signatures:",
                    completedSignatures.map { "- \($0)" }.joined(separator: "\n")
                ].joined(separator: "\n")
            )

        case .stop:
            return nil

        case .forceStop(let reason):
            return ChatMessage(
                role: .system,
                content: "Task halted: \(reason). Summarize what was accomplished so the user has a clear picture."
            )
        }
    }
}

// MARK: - Research Subagent (Context Access Layer L6)

/// A read-only subagent with its own isolated context window. The parent model
/// delegates exploration to it via the `research` tool. The subagent runs a
/// mini tool loop (read-only tools only) and returns a bounded summary.
@MainActor
final class ResearchSubagent {
    struct Result: Sendable {
        let summary: String
        let filesRead: [String]
        let turnsUsed: Int
    }

    static let maxTurns = 5

    static func run(
        goal: String,
        specificFiles: [String] = [],
        projectRoot: URL,
        aiService: AIService,
        fileSystemService: FileSystemService,
        pathValidator: PathValidator,
        vectorStoreService: VectorStoreService? = nil,
        embedder: (any MemoryEmbeddingGenerating)? = nil,
        codebaseIndex: CodebaseIndexProtocol? = nil
    ) async throws -> Result {
        let coordinator = ChatHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = coordinator.currentConversationId

        var brief = goal
        if !specificFiles.isEmpty {
            brief += "\n\nFocus on these files:\n" + specificFiles.map { "- \($0)" }.joined(separator: "\n")
        }
        brief += "\n\nUse read, ls, glob, search, and context tools to explore. When you have a clear picture, provide a concise summary of findings."

        coordinator.append(ChatMessage(role: .user, content: brief))

        let tools: [AITool] = [
            ReadFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator),
            ListFilesTool(pathValidator: pathValidator),
            FindFileTool(pathValidator: pathValidator),
            SearchProjectTool(index: codebaseIndex, projectRoot: projectRoot),
            ContextTool(vectorStoreService: vectorStoreService, embedder: embedder)
        ]

        var allFilesRead: Set<String> = []
        var turnCount = 0
        var currentMessages = coordinator.requestMessages
        var lastResponse: AIServiceResponse?

        while turnCount < Self.maxTurns {
            let request = AIServiceHistoryRequest(
                messages: currentMessages,
                tools: tools,
                mode: .agent,
                projectRoot: projectRoot,
                runId: nil,
                stage: AIRequestStage.tool_loop
            )

            let response = try await aiService.sendMessage(request)
            lastResponse = response

            guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
                return Result(
                    summary: response.content ?? "(no summary)",
                    filesRead: Array(allFilesRead),
                    turnsUsed: turnCount + 1
                )
            }

            var toolResults: [ChatMessage] = []
            for call in toolCalls {
                if call.name == "read", let path = call.arguments["path"] as? String {
                    allFilesRead.insert(path)
                }
                let result = try await executeToolCall(call, tools: tools, projectRoot: projectRoot)
                toolResults.append(result)
            }

            coordinator.append(ChatMessage(role: .assistant, content: response.content ?? "", tool: ChatMessageToolContext(toolCalls: toolCalls)))
            for result in toolResults {
                coordinator.append(result)
            }

            currentMessages = coordinator.requestMessages
            turnCount += 1
        }

        return Result(
            summary: lastResponse?.content ?? "Reached maximum research turns (\(Self.maxTurns)). Partial findings above.",
            filesRead: Array(allFilesRead),
            turnsUsed: Self.maxTurns
        )
    }

    private static func executeToolCall(
        _ call: AIToolCall,
        tools: [AITool],
        projectRoot: URL
    ) async throws -> ChatMessage {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return ChatMessage(
                role: .tool,
                content: "Unknown tool: \(call.name)",
                tool: ChatMessageToolContext(toolName: call.name, toolStatus: .failed, target: ToolInvocationTarget(targetFile: nil, toolCallId: call.id))
            )
        }
        do {
            let result = try await tool.execute(arguments: ToolArguments(call.arguments))
            return ChatMessage(
                role: .tool,
                content: result,
                tool: ChatMessageToolContext(toolName: call.name, toolStatus: .completed, target: ToolInvocationTarget(targetFile: nil, toolCallId: call.id))
            )
        } catch {
            return ChatMessage(
                role: .tool,
                content: "Error: \(error.localizedDescription)",
                tool: ChatMessageToolContext(toolName: call.name, toolStatus: .failed, target: ToolInvocationTarget(targetFile: nil, toolCallId: call.id))
            )
        }
    }
}

/// Tool that delegates to the ResearchSubagent. Available in agent mode.
struct ResearchTool: AITool, @unchecked Sendable {
    let name = "research"
    let description = "Delegate a research/exploration task to a subagent with its own isolated context. Use this when you need to explore the codebase (read files, search, list directories) without cluttering your main context. Provide a specific goal and optionally a list of files to focus on."

    let aiServiceProvider: () -> AIService?
    let projectRootProvider: () -> URL?
    let fileSystemService: FileSystemService
    let pathValidator: PathValidator
    let vectorStoreService: VectorStoreService?
    let embedder: (any MemoryEmbeddingGenerating)?
    let codebaseIndexProvider: () -> CodebaseIndexProtocol?

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "goal": [
                    "type": "string",
                    "description": "What to research. Be specific about what information you need."
                ],
                "files": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional list of file paths to focus on."
                ]
            ],
            "required": ["goal"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        guard let goal = raw["goal"] as? String else {
            return "Missing 'goal' argument."
        }
        let files = (raw["files"] as? [String]) ?? []
        guard let projectRoot = projectRootProvider() else {
            return "No project root available."
        }
        guard let aiService = aiServiceProvider() else {
            return "No AI service available for research subagent."
        }

        let codebaseIndex = codebaseIndexProvider()

        let result = try await ResearchSubagent.run(
            goal: goal,
            specificFiles: files,
            projectRoot: projectRoot,
            aiService: aiService,
            fileSystemService: fileSystemService,
            pathValidator: pathValidator,
            vectorStoreService: vectorStoreService,
            embedder: embedder,
            codebaseIndex: codebaseIndex
        )

        return """
        research complete (used \(result.turnsUsed) turn(s)):
        summary: \(result.summary)
        files read: \(result.filesRead.isEmpty ? "none" : result.filesRead.joined(separator: ", "))
        """
    }
}
