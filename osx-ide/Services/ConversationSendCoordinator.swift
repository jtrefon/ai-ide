import Foundation

@MainActor
final class ConversationSendCoordinator {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    var clearStreamingBuffer: (@MainActor () -> Void)? {
        didSet {
            toolLoopHandler.clearStreamingBuffer = clearStreamingBuffer
        }
    }

    private let initialResponseHandler: InitialResponseHandler
    private let toolLoopHandler: ToolLoopHandler
    private let qaReviewHandler: QAReviewHandler
    private let finalResponseHandler: FinalResponseHandler

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

        self.initialResponseHandler = InitialResponseHandler(
            aiInteractionCoordinator: aiInteractionCoordinator,
            historyCoordinator: historyCoordinator
        )
        self.toolLoopHandler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator,
            clearStreamingBuffer: clearStreamingBuffer
        )
        self.qaReviewHandler = QAReviewHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator
        )
        self.finalResponseHandler = FinalResponseHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator
        )
    }

    func send(
        _ request: SendRequest
    ) async throws {
        let sendStartTime = ContinuousClock.now
        await AppLogger.shared.debug(
            category: .conversation,
            message: "send.start",
            context: AppLogger.LogCallContext(metadata: [
                "conversationId": String(request.conversationId.prefix(8)),
                "mode": request.mode.rawValue,
                "messageCount": historyCoordinator.messages.count
            ])
        )

        // §7: Inject recovery context if previous turn was interrupted (e.g. network error)
        await injectRecoveryContextIfNeeded(request: request)

        let flowStartTime = ContinuousClock.now
        let response = try await executeConversationFlow(request)
        let flowDuration = flowStartTime.duration(to: ContinuousClock.now)
        await AppLogger.shared.debug(
            category: .conversation,
            message: "send.flow_complete",
            context: AppLogger.LogCallContext(metadata: [
                "flowDuration": flowDuration.description
            ])
        )
        
        finalResponseHandler.appendFinalMessageAndLog(
            response: response,
            conversationId: request.conversationId,
            draftAssistantMessageId: request.draftAssistantMessageId?.uuidString
        )

        trimOldMessagesIfNeeded()
        
        let totalDuration = sendStartTime.duration(to: ContinuousClock.now)
        await AppLogger.shared.debug(
            category: .conversation,
            message: "send.complete",
            context: AppLogger.LogCallContext(metadata: [
                "totalDuration": totalDuration.description
            ])
        )
    }

    private func executeConversationFlow(_ request: SendRequest) async throws -> AIServiceResponse {
        if request.usesLocalModel {
            let localTools = LocalModelToolProvider.safeTools(from: request.availableTools)
            return try await executeLocalModelToolLoop(
                request: request,
                localTools: localTools
            )
        }

        await OrchestrationRunStore.shared.setProjectRoot(request.projectRoot)

        let graph = ConversationFlowGraphFactory.makeGraph(
            request: request,
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            initialResponseHandler: initialResponseHandler,
            toolLoopHandler: toolLoopHandler,
            finalResponseHandler: finalResponseHandler,
            qaReviewHandler: qaReviewHandler,
            qaReviewEnabled: request.qaReviewEnabled
        )

        let runner = OrchestrationGraphRunner(graph: graph)
        let finalState = try await runner.run(initialState: OrchestrationState(
            request: request,
            transition: .next(graph.entryNodeId)
        ))

        guard let response = finalState.response else {
            throw AppError.unknown("ConversationSendCoordinator: orchestration ended without response")
        }

        return response
    }

    private func executeLocalModelToolLoop(
        request: SendRequest,
        localTools: [AITool]
    ) async throws -> AIServiceResponse {
        let maxIterations = 8
        var callFrequencies: [CallSignature: Int] = [:]
        let maxSameCall = 3
        var promptedForExecution = false

        for _ in 0..<maxIterations {
            let messages = historyCoordinator.messages.filter { !$0.isDraft }
            let result = await aiInteractionCoordinator.sendMessageWithRetry(
                AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: messages,
                    mediaAttachments: request.mediaAttachments,
                    tools: localTools,
                    mode: request.mode,
                    projectRoot: request.projectRoot,
                    runId: request.runId,
                    stage: nil,
                    conversationId: request.conversationId,
                    usesLocalModel: true
                )
            )
            let response = try result.get()
            let rawContent = response.content ?? ""

            let parsed = ChatPromptBuilder.parseModelResponse(rawContent)

            let toolCalls: [AIToolCall]
            if let structured = response.toolCalls, !structured.isEmpty {
                toolCalls = structured
            } else {
                toolCalls = parsed.toolCalls
            }

            clearStreamingBuffer?()

            guard !toolCalls.isEmpty else {
                if !promptedForExecution, looksLikePlanWithoutAction(rawContent) {
                    promptedForExecution = true
                    let planMsg = ChatMessage(
                        role: .system,
                        content: "You outlined a plan above but did not execute any steps. " +
                            "Immediately execute the first step by calling the appropriate tool. " +
                            "Do not repeat the plan — just execute."
                    )
                    historyCoordinator.append(planMsg)
                    continue
                }
                return response
            }

            var shouldBreak = false
            for call in toolCalls {
                let sig = CallSignature(name: call.name, arguments: call.arguments)
                callFrequencies[sig, default: 0] += 1
                if callFrequencies[sig]! >= maxSameCall {
                    shouldBreak = true
                }
            }
            if shouldBreak {
                return response
            }

            let displayContent = ChatPromptBuilder.contentForDisplay(from: rawContent)
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: displayContent.isEmpty ? "Working..." : displayContent,
                context: ChatMessageContentContext(reasoning: parsed.reasoning),
                tool: ChatMessageToolContext(toolCalls: toolCalls)
            )
            historyCoordinator.append(assistantMsg)

            let toolResults = await toolExecutionCoordinator.executeToolCalls(
                toolCalls,
                availableTools: localTools,
                conversationId: request.conversationId,
                onProgressMessage: { progressMsg in
                    if progressMsg.toolStatus == .executing {
                        self.historyCoordinator.setLiveToolMessage(progressMsg)
                    } else {
                        self.historyCoordinator.clearLiveToolMessage(progressMsg.toolCallId ?? "")
                        self.historyCoordinator.append(progressMsg)
                    }
                }
            )
            for msg in toolResults {
                historyCoordinator.append(msg)
                if msg.content.contains("Tool not found") {
                    let available = localTools.map(\.name).sorted().joined(separator: ", ")
                    let correctionMsg = ChatMessage(
                        role: .system,
                        content: "Tool unavailable. Available tools: \(available). Use one of these instead."
                    )
                    historyCoordinator.append(correctionMsg)
                }
            }
        }

        let result = await aiInteractionCoordinator.sendMessageWithRetry(
            AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.requestMessages,
                mediaAttachments: request.mediaAttachments,
                tools: localTools,
                mode: request.mode,
                projectRoot: request.projectRoot,
                runId: request.runId,
                stage: nil,
                conversationId: request.conversationId,
                usesLocalModel: true
            )
        )
        return try result.get()
    }

    private func looksLikePlanWithoutAction(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasPlanMarker = lower.contains("plan:") || lower.contains("**plan**") || lower.contains("# plan")
        let hasSteps = lower.contains("1.") || lower.contains("step 1") || lower.contains("step one")
        let hasToolCall = lower.contains("read_file") || lower.contains("search_project") ||
                          lower.contains("find_file") || lower.contains("grep") ||
                          lower.contains("list_dir") || lower.contains("get_project_structure")
        return hasPlanMarker && hasSteps && !hasToolCall
    }

    private struct CallSignature: Hashable {
        let name: String
        let arguments: [String: String]

        init(name: String, arguments: [String: Any]) {
            self.name = name
            self.arguments = arguments.compactMapValues { $0 as? String }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            let sorted = arguments.keys.sorted().map { "\($0):\(arguments[$0] ?? "")" }.joined()
            hasher.combine(sorted)
        }

        static func == (lhs: CallSignature, rhs: CallSignature) -> Bool {
            lhs.name == rhs.name && lhs.arguments == rhs.arguments
        }
    }

    // MARK: - Context management

    /// If the coordinator's strategy is `.compaction` and assistant messages
    /// exceed a conservative budget, append a compaction checkpoint. If
    /// `.slidingWindow`, skip compaction — the model's large context window
    /// and prefix cache handle the full chain.
    private func trimOldMessagesIfNeeded() {
        guard historyCoordinator.strategy == .compaction else { return }
        let assistantCount = historyCoordinator.committedMessages.filter { $0.role == .assistant }.count
        let maxAssistantMessages = 12
        guard assistantCount > maxAssistantMessages else { return }
        historyCoordinator.compact(
            summary: "Earlier turns compacted to conserve context. Use context(query:) for details."
        )
    }

    // MARK: - Recovery Context (Context Access Layer §7)

    /// Detects whether the previous turn was interrupted (e.g. network error or crash)
    /// and injects a recovery system message so the model can resume with context.
    private func injectRecoveryContextIfNeeded(request: SendRequest) async {
        let messages = historyCoordinator.messages
        guard messages.count >= 2 else { return }

        let lastUser = messages.last(where: { $0.role == .user })
        let lastAssistant = messages.last(where: { $0.role == .assistant })

        guard let lastUser, let lastAssistant else { return }

        // Detect interruption: last assistant has no completion content AND
        // the user message is a brief continuation ("continue", "go on", etc.)
        let isBriefContinuation = lastUser.content.trimmingCharacters(in: .whitespacesAndNewlines).count < 30
            && !lastUser.content.contains("implement")
            && !lastUser.content.contains("write")
            && !lastUser.content.contains("create")
            && !lastUser.content.contains("fix")
            && !lastUser.content.contains("refactor")

        let assistantSeemsIncomplete = lastAssistant.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (!lastAssistant.content.contains("done")
                && !lastAssistant.content.contains("completed")
                && !lastAssistant.content.contains("finished")
                && !lastAssistant.content.contains("implemented")
                && !lastAssistant.content.contains("summary"))

        guard isBriefContinuation || assistantSeemsIncomplete else { return }

        // Build recovery context
        var context = "[Recovery: The previous response was interrupted. You are in \(request.mode.rawValue) mode."

        if let plan = await ConversationPlanStore.shared.get(conversationId: request.conversationId) {
            let progress = PlanChecklistTracker.progress(in: plan)
            if progress.total > 0 {
                context += " Plan progress: \(progress.completed)/\(progress.total) tasks complete."
            }
        }

        context += " Continue working on the original request. Do not restart from scratch — pick up where you left off.]"

        // Inject recovery context as a system message (appended before tool loop starts)
        let recoveryMsg = ChatMessage(role: .system, content: context)
        historyCoordinator.append(recoveryMsg)
    }
}
