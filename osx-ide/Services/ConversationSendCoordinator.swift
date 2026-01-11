import Foundation

@MainActor
final class ConversationSendCoordinator {
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
        userInput: String,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        availableTools: [AITool],
        cancelledToolCallIds: @escaping () -> Set<String>
    ) async throws {
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
                "summary": foldResult.entry.summary,
            ])
        }

        var currentResponse = try await aiInteractionCoordinator
            .sendMessageWithRetry(
                messages: historyCoordinator.messages,
                explicitContext: explicitContext,
                tools: availableTools,
                mode: mode,
                projectRoot: projectRoot
            )
            .get()

        if mode == .agent,
           currentResponse.toolCalls?.isEmpty ?? true,
           let content = currentResponse.content,
           ChatPromptBuilder.shouldForceToolFollowup(content: content),
           let lastUserMessage = historyCoordinator.messages.last(where: { $0.role == .user })
        {
            let followupSystem = ChatMessage(
                role: .system,
                content: "You indicated you will implement changes, but you returned no tool calls. In Agent mode, you MUST now proceed by calling the appropriate tools. Return tool calls now."
            )

            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(
                    messages: historyCoordinator.messages + [followupSystem, lastUserMessage],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                )
                .get()
        }

        var toolIteration = 0
        let maxIterations = (mode == .agent) ? 12 : 5

        while let toolCalls = currentResponse.toolCalls,
              !toolCalls.isEmpty,
              toolIteration < maxIterations {
            toolIteration += 1

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

            let toolCallsCount = toolCalls.count
            let toolCallsMetadata = toolCalls.map {
                [
                    "id": $0.id,
                    "name": $0.name,
                ]
            }

            Task.detached(priority: .utility) {
                await AppLogger.shared.info(
                    category: .conversation, message: "chat.assistant_tool_calls",
                    metadata: [
                        "conversationId": conversationId,
                        "toolCalls": toolCallsCount,
                    ])
                await ConversationLogStore.shared.append(
                    conversationId: conversationId,
                    type: "chat.assistant_tool_calls",
                    data: [
                        "content": split.content,
                        "toolCalls": toolCallsMetadata,
                    ]
                )
            }

            // Mark cancelled tool calls immediately.
            let cancelled = cancelledToolCallIds()
            for call in toolCalls where cancelled.contains(call.id) {
                historyCoordinator.updateMessageStatus(toolCallId: call.id, status: .failed, content: "Cancelled by user")
            }

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

            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(
                    messages: historyCoordinator.messages,
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                )
                .get()
        }

        if ChatPromptBuilder.needsReasoningFormatCorrection(text: currentResponse.content ?? "") {
            let correctionSystem = ChatMessage(
                role: .system,
                content: "Your <ide_reasoning> block must include ALL four sections: Analyze, Research, Plan, Reflect."
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                )
                .get()
        }

        if ChatPromptBuilder.isLowQualityReasoning(text: currentResponse.content ?? "") {
            let correctionSystem = ChatMessage(
                role: .system,
                content: "Your <ide_reasoning> block is too vague (placeholders like '...' are not allowed). Provide concise, concrete bullet points for EACH section: Analyze, Research, Plan, Reflect. If unknown, write 'N/A' and state what information is needed."
            )
            currentResponse = try await aiInteractionCoordinator
                .sendMessageWithRetry(
                    messages: historyCoordinator.messages + [correctionSystem],
                    explicitContext: explicitContext,
                    tools: availableTools,
                    mode: mode,
                    projectRoot: projectRoot
                )
                .get()
        }

        let splitFinal = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "No response received.")
        historyCoordinator.append(
            ChatMessage(
                role: .assistant,
                content: splitFinal.content,
                context: ChatMessageContentContext(reasoning: splitFinal.reasoning)
            )
        )

        let hasReasoning = (splitFinal.reasoning?.isEmpty == false)
        let contentLength = splitFinal.content.count
        let reasoningText = splitFinal.reasoning

        Task.detached(priority: .utility) {
            await AppLogger.shared.info(
                category: .conversation, message: "chat.assistant_message",
                metadata: [
                    "conversationId": conversationId,
                    "contentLength": contentLength,
                    "hasReasoning": hasReasoning,
                ])
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.assistant_message",
                data: [
                    "content": splitFinal.content,
                    "reasoning": reasoningText as Any,
                ]
            )
        }
    }
}
