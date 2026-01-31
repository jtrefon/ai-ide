import Foundation

@MainActor
final class ConversationSendCoordinator {
    struct SendRequest {
        let userInput: String
        let explicitContext: String?
        let mode: AIMode
        let projectRoot: URL
        let conversationId: String
        let runId: String
        let availableTools: [AITool]
        let cancelledToolCallIds: @Sendable () -> Set<String>
        let qaReviewEnabled: Bool
    }

    private struct ToolLoopResult {
        let response: AIServiceResponse
        let lastToolCalls: [AIToolCall]
        let lastToolResults: [ChatMessage]
    }

    private struct RunSnapshotPayload {
        let runId: String
        let conversationId: String
        let phase: String
        let iteration: Int?
        let userInput: String
        let assistantDraft: String?
        let failureReason: String?
        let toolCalls: [AIToolCall]
        let toolResults: [ChatMessage]
    }

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

    func send(
        _ request: SendRequest
    ) async throws {
        try await foldConversationIfNeeded(projectRoot: request.projectRoot)
        let response = try await executeConversationFlow(request)
        appendFinalMessageAndLog(response: response, conversationId: request.conversationId)
    }

    private func executeConversationFlow(_ request: SendRequest) async throws -> AIServiceResponse {
        let initialResponse = try await sendInitialResponse(
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools
        )

        await appendRunSnapshot(payload: RunSnapshotPayload(
            runId: request.runId,
            conversationId: request.conversationId,
            phase: "initial_response",
            iteration: nil,
            userInput: request.userInput,
            assistantDraft: initialResponse.content,
            failureReason: nil,
            toolCalls: initialResponse.toolCalls ?? [],
            toolResults: []
        ))

        let toolLoopResult = try await handleToolLoopIfNeeded(
            response: initialResponse,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            conversationId: request.conversationId,
            availableTools: request.availableTools,
            cancelledToolCallIds: request.cancelledToolCallIds,
            runId: request.runId,
            userInput: request.userInput
        )

        var response = toolLoopResult.response

        response = try await performToolOutputReviewIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            qaReviewEnabled: request.qaReviewEnabled,
            toolResults: toolLoopResult.lastToolResults,
            runId: request.runId,
            userInput: request.userInput
        )

        response = try await performQualityReviewIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            qaReviewEnabled: request.qaReviewEnabled
        )

        response = try await applyReasoningCorrectionsIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools
        )

        response = try await enforceDeliveryCompletionIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools
        )

        response = try await requestFinalResponseIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            projectRoot: request.projectRoot,
            toolResults: toolLoopResult.lastToolResults
        )

        return response
    }

    private func foldConversationIfNeeded(projectRoot: URL) async throws {
        let thresholds = ConversationFoldingThresholds()
        if let foldResult = try await ConversationFoldingService.fold(
            messages: historyCoordinator.messages,
            projectRoot: projectRoot,
            thresholds: thresholds
        ) {
            historyCoordinator.removeOldestMessages(count: foldResult.foldedMessageCount)
            await AIToolTraceLogger.shared.log(type: "chat.context_folded", data: [
                "foldId": foldResult.entry.id,
                "foldedMessageCount": foldResult.foldedMessageCount,
                "summary": foldResult.entry.summary
            ])
        }
    }

    private func sendInitialResponse(
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        availableTools: [AITool]
    ) async throws -> AIServiceResponse {
        var response = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages,
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot
            ))
            .get()

        if mode == .agent,
           response.toolCalls?.isEmpty ?? true,
           let content = response.content,
           ChatPromptBuilder.shouldForceToolFollowup(content: content),
           let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user }) {
            let followupSystem = ChatMessage(
                role: .system,
                content: "You indicated you will implement changes, but you returned no tool calls. " +
                    "In Agent mode, you MUST now proceed by calling the appropriate tools. " +
                    "Return tool calls now."
            )

            response = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: historyCoordinator.messages + [followupSystem, lastUserMessage],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                ))
                .get()
        }

        return response
    }

    private func handleToolLoopIfNeeded(
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
        let maxIterations = (mode == .agent) ? 12 : 5

        while let toolCalls = currentResponse.toolCalls,
              !toolCalls.isEmpty,
              toolIteration < maxIterations {
            toolIteration += 1
            lastToolCalls = toolCalls

            await AIToolTraceLogger.shared.log(type: "chat.tool_loop_iteration", data: [
                "mode": mode.rawValue,
                "iteration": toolIteration,
                "toolCalls": toolCalls.count
            ])

            let split = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "")
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning),
                tool: ChatMessageToolContext(toolCalls: toolCalls)
            )
            historyCoordinator.append(assistantMsg)

            logAssistantToolCalls(
                conversationId: conversationId,
                content: split.content,
                toolCalls: toolCalls
            )

            markCancelledToolCalls(toolCalls: toolCalls, cancelledToolCallIds: cancelledToolCallIds())

            let toolResults = await toolExecutionCoordinator.executeToolCalls(
                toolCalls,
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
                } else {
                    historyCoordinator.append(msg)
                }
            }

            lastToolResults = toolResults

            await appendRunSnapshot(payload: RunSnapshotPayload(
                runId: runId,
                conversationId: conversationId,
                phase: "tool_loop",
                iteration: toolIteration,
                userInput: userInput,
                assistantDraft: currentResponse.content,
                failureReason: failureReason(from: toolResults),
                toolCalls: toolCalls,
                toolResults: toolResults
            ))

            let failureRecoveryMessage = toolFailureRecoveryMessage(
                toolCalls: toolCalls,
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

            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: followupMessages,
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                ))
                .get()

            if mode == .agent,
               currentResponse.toolCalls?.isEmpty ?? true,
               let content = currentResponse.content,
               ChatPromptBuilder.shouldForceToolFollowup(content: content),
               let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user }) {
                let followupSystem = ChatMessage(
                    role: .system,
                    content: "You indicated you will implement changes, but you returned no tool calls. " +
                        "In Agent mode, you MUST now proceed by calling the appropriate tools. " +
                        "Return tool calls now."
                )
                currentResponse = try await aiInteractionCoordinator
                    .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                        messages: historyCoordinator.messages + [followupSystem, lastUserMessage],
                        explicitContext: explicitContext,
                        tools: availableTools,
                        mode: mode,
                        projectRoot: projectRoot
                    ))
                    .get()
            }

            let trimmedContent = currentResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedContent.isEmpty, currentResponse.toolCalls?.isEmpty == false {
                consecutiveEmptyToolCallResponses += 1
            } else {
                consecutiveEmptyToolCallResponses = 0
            }

            if consecutiveEmptyToolCallResponses >= 2 {
                currentResponse = try await requestFinalResponseForStalledToolLoop(
                    explicitContext: explicitContext,
                    projectRoot: projectRoot,
                    userInput: userInput,
                    toolResults: lastToolResults
                )
                break
            }
        }

        return ToolLoopResult(
            response: currentResponse,
            lastToolCalls: lastToolCalls,
            lastToolResults: lastToolResults
        )
    }

    private func performToolOutputReviewIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        qaReviewEnabled: Bool,
        toolResults: [ChatMessage],
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse {
        guard qaReviewEnabled, mode == .agent else { return response }
        guard !toolResults.isEmpty else { return response }

        let toolSummary = toolResultsSummaryText(toolResults)
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.isEmpty else { return response }

        let qaSystem = ChatMessage(
            role: .system,
            content: "You are the QA reviewer for tool execution results. Validate the assistant draft against " +
                "the tool outputs and user request. If steps are missing or tool failures occurred, " +
                "revise the draft to include recovery guidance or next actions. " +
                "Return the improved draft response only. Do not call tools. Do not include <ide_reasoning>."
        )
        let qaUser = ChatMessage(
            role: .user,
            content: "User request:\n\(userInput)\n\nTool outputs:\n\(toolSummary)\n\nDraft response:\n\(draft)"
        )

        let qaResponse = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [qaSystem, qaUser],
                explicitContext: explicitContext,
                tools: [],
                mode: .chat,
                projectRoot: projectRoot
            ))
            .get()

        await appendRunSnapshot(payload: RunSnapshotPayload(
            runId: runId,
            conversationId: historyCoordinator.currentConversationId,
            phase: "tool_output_review",
            iteration: nil,
            userInput: userInput,
            assistantDraft: qaResponse.content,
            failureReason: nil,
            toolCalls: [],
            toolResults: toolResults
        ))

        let qaContent = qaResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = qaContent?.isEmpty == false ? qaResponse.content : response.content
        return AIServiceResponse(content: finalContent, toolCalls: nil)
    }


    private func performQualityReviewIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        qaReviewEnabled: Bool
    ) async throws -> AIServiceResponse {
        guard qaReviewEnabled, mode == .agent else { return response }
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.isEmpty else { return response }

        let qaSystem = ChatMessage(
            role: .system,
            content: "You are the QA reviewer. Review the assistant draft response for correctness, completeness, " +
                "and adherence to the user request. Return the improved final response only. " +
                "If the draft is already perfect, repeat it verbatim. Do not call tools. Do not include <ide_reasoning>."
        )
        let qaUser = ChatMessage(
            role: .user,
            content: "Review and refine this draft response:\n\n\(draft)"
        )

        let qaResponse = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [qaSystem, qaUser],
                explicitContext: explicitContext,
                tools: [],
                mode: .chat,
                projectRoot: projectRoot
            ))
            .get()

        let qaContent = qaResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = qaContent?.isEmpty == false ? qaResponse.content : response.content
        return AIServiceResponse(content: finalContent, toolCalls: nil)
    }

    private func toolFailureRecoveryMessage(
        toolCalls: [AIToolCall],
        toolResults: [ChatMessage]
    ) -> ChatMessage? {
        let failedToolResults = toolResults.filter {
            $0.isToolExecution && $0.toolStatus == .failed
        }
        guard !failedToolResults.isEmpty else { return nil }

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
            let output = toolOutputText(from: result)
            return "- \(toolName) (\(toolCallId)): \(output) [\(argumentSummary)]"
        }

        let systemMessage = ChatMessage(
            role: .system,
            content: [
                "Tool execution failures detected.",
                "Review the failures below and adjust your approach.",
                "If a failure is environmental, network, or resource-related, propose a fallback plan or use different parameters.",
                "Do not repeat the same failing call without changes.",
                "",
                failureDetails.joined(separator: "\n")
            ].joined(separator: "\n")
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

    private func requestFinalResponseIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        projectRoot: URL,
        toolResults: [ChatMessage]
    ) async throws -> AIServiceResponse {
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard draft.isEmpty else { return response }

        let toolSummary = toolResultsSummaryText(toolResults)
        let correctionContent: String
        if toolResults.isEmpty {
            correctionContent = "You returned no user-visible response. Provide a final response in plain text now. " +
                "Do not call tools."
        } else {
            correctionContent = "You returned no user-visible response after tool execution. " +
                "Provide a final response in plain text now. Do not call tools.\n\nTool outputs:\n\(toolSummary)"
        }
        let correctionSystem = ChatMessage(
            role: .system,
            content: correctionContent
        )

        let followup = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages + [correctionSystem],
                explicitContext: explicitContext,
                tools: [],
                mode: .chat,
                projectRoot: projectRoot
            ))
            .get()

        let followupContent = followup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = followupContent?.isEmpty == false
            ? followup.content
            : response.content
        let resolvedContent = (finalContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? finalContent
            : "I wasn't able to generate a final response. " +
                "Here is a summary of tool outputs:\n\n\(toolSummary)\n\n" +
                "Please retry or clarify the next step."
        return AIServiceResponse(content: resolvedContent, toolCalls: nil)
    }

    private func requestFinalResponseForStalledToolLoop(
        explicitContext: String?,
        projectRoot: URL,
        userInput: String,
        toolResults: [ChatMessage]
    ) async throws -> AIServiceResponse {
        let toolSummary = toolResultsSummaryText(toolResults)
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

        let followup = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [correctionSystem, correctionUser],
                explicitContext: explicitContext,
                tools: [],
                mode: .chat,
                projectRoot: projectRoot
            ))
            .get()

        let followupContent = followup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = followupContent?.isEmpty == false
            ? followup.content
            : "I attempted to gather context via tools but did not receive a complete response. Please retry."
        return AIServiceResponse(content: finalContent, toolCalls: nil)
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

    private func appendRunSnapshot(payload: RunSnapshotPayload) async {
        let snapshot = OrchestrationRunSnapshot(
            runId: payload.runId,
            conversationId: payload.conversationId,
            phase: payload.phase,
            iteration: payload.iteration,
            timestamp: Date(),
            userInput: payload.userInput,
            assistantDraft: payload.assistantDraft,
            failureReason: payload.failureReason,
            toolCalls: toolCallSummaries(payload.toolCalls),
            toolResults: toolResultSummaries(payload.toolResults)
        )
        try? await OrchestrationRunStore.shared.appendSnapshot(snapshot)
    }

    private func toolCallSummaries(_ toolCalls: [AIToolCall]) -> [OrchestrationRunSnapshot.ToolCallSummary] {
        toolCalls.map {
            OrchestrationRunSnapshot.ToolCallSummary(
                id: $0.id,
                name: $0.name,
                argumentKeys: Array($0.arguments.keys).sorted()
            )
        }
    }

    private func toolResultSummaries(_ toolResults: [ChatMessage]) -> [OrchestrationRunSnapshot.ToolResultSummary] {
        toolResults.compactMap { message in
            guard let toolCallId = message.toolCallId else { return nil }
            let output = toolOutputText(from: message)
            return OrchestrationRunSnapshot.ToolResultSummary(
                toolCallId: toolCallId,
                toolName: message.toolName ?? "unknown_tool",
                status: message.toolStatus?.rawValue ?? "unknown",
                targetFile: message.targetFile,
                outputPreview: truncate(output, limit: 1200)
            )
        }
    }

    private func toolResultsSummaryText(_ toolResults: [ChatMessage]) -> String {
        let lines = toolResults.compactMap { message -> String? in
            guard let toolCallId = message.toolCallId else { return nil }
            let status = message.toolStatus?.rawValue ?? "unknown"
            let preview = truncate(toolOutputText(from: message), limit: 400)
            return "- \(message.toolName ?? "unknown_tool") (\(toolCallId)) [\(status)]: \(preview)"
        }
        return lines.isEmpty ? "No tool outputs." : lines.joined(separator: "\n")
    }

    private func failureReason(from toolResults: [ChatMessage]) -> String? {
        let failures = toolResults.filter { $0.isToolExecution && $0.toolStatus == .failed }
        guard !failures.isEmpty else { return nil }
        let summary = failures.compactMap { message -> String? in
            guard let toolCallId = message.toolCallId else { return nil }
            let preview = truncate(toolOutputText(from: message), limit: 300)
            return "\(message.toolName ?? "unknown_tool") (\(toolCallId)): \(preview)"
        }
        return summary.joined(separator: "\n")
    }

    private func toolOutputText(from message: ChatMessage) -> String {
        guard message.isToolExecution else { return message.content }
        if let envelope = ToolExecutionEnvelope.decode(from: message.content) {
            if let payload = envelope.payload?.trimmingCharacters(in: .whitespacesAndNewlines),
               !payload.isEmpty {
                return payload
            }
            return envelope.message
        }
        return message.content
    }

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }

    private func applyReasoningCorrectionsIfNeeded(
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

    private func enforceDeliveryCompletionIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        availableTools: [AITool]
    ) async throws -> AIServiceResponse {
        guard mode == .agent else { return response }
        guard let status = ChatPromptBuilder.deliveryStatus(from: response.content ?? "") else { return response }
        guard status == .needsWork else { return response }

        let correctionSystem = ChatMessage(
            role: .system,
            content: "Your Delivery section indicates the task is not complete. " +
                "Continue the work now. When finished, set Delivery: DONE and provide a user-visible response. " +
                "If you need tools, call them."
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

    private func appendFinalMessageAndLog(response: AIServiceResponse, conversationId: String) {
        let splitFinal = ChatPromptBuilder.splitReasoning(from: response.content ?? "No response received.")
        let trimmedContent = splitFinal.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent = trimmedContent.isEmpty
            ? "Assistant returned no user-visible response. Please retry or rephrase."
            : splitFinal.content
        let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: response.content ?? "")
        let deliveryStatusText: String
        switch deliveryStatus {
        case .done:
            deliveryStatusText = "done"
        case .needsWork:
            deliveryStatusText = "needs_work"
        case .none:
            deliveryStatusText = "missing"
        }
        historyCoordinator.append(
            ChatMessage(
                role: .assistant,
                content: displayContent,
                context: ChatMessageContentContext(reasoning: splitFinal.reasoning)
            )
        )

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
                    "deliveryStatus": deliveryStatusText
                ])
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.assistant_message",
                data: [
                    "content": displayContent,
                    "reasoning": reasoningText as Any,
                    "deliveryStatus": deliveryStatusText
                ]
            )
        }
    }
}
