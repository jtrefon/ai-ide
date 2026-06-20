import Foundation

@MainActor
final class ConversationSendCoordinator {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    var clearStreamingBuffer: (@MainActor () -> Void)?

    private let foldingHandler: ConversationFoldingHandler
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

        self.foldingHandler = ConversationFoldingHandler()
        self.initialResponseHandler = InitialResponseHandler(
            aiInteractionCoordinator: aiInteractionCoordinator,
            historyCoordinator: historyCoordinator
        )
        self.toolLoopHandler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
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
        
        let foldStartTime = ContinuousClock.now
        try await foldingHandler.foldIfNeeded(
            historyCoordinator: historyCoordinator,
            projectRoot: request.projectRoot,
            mode: request.mode
        )
        let foldDuration = foldStartTime.duration(to: ContinuousClock.now)
        await AppLogger.shared.debug(
            category: .conversation,
            message: "send.fold_complete",
            context: AppLogger.LogCallContext(metadata: [
                "foldDuration": foldDuration.description,
                "messageCount": historyCoordinator.messages.count
            ])
        )
        
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
        let maxIterations = 5
        var callFrequencies: [CallSignature: Int] = [:]
        let maxSameCall = 3
        var promptedForExecution = false

        for iteration in 0..<maxIterations {
            let messages = historyCoordinator.messages
            let result = await aiInteractionCoordinator.sendMessageWithRetry(
                AIInteractionCoordinator.SendMessageWithRetryRequest(
                    messages: messages,
                    mediaAttachments: request.mediaAttachments,
                    explicitContext: request.explicitContext,
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

            // Prefer structured tool calls from the MLX framework (cleaner parsing)
            let toolCalls: [AIToolCall]
            if let structured = response.toolCalls, !structured.isEmpty {
                toolCalls = structured
            } else {
                let parsed = ChatPromptBuilder.parseModelResponse(rawContent)
                toolCalls = parsed.toolCalls
            }

            // No tool calls
            guard !toolCalls.isEmpty else {
                // If the response looks like a plan with no execution, prompt the model once to act
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

            // Count call frequencies and break if same call seen 3+ times
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

            // Clear streaming buffer so consolidation pass starts fresh
            await clearStreamingBuffer?()

            // Execute tool calls
            let toolResults = await toolExecutionCoordinator.executeToolCalls(
                toolCalls,
                availableTools: localTools,
                conversationId: request.conversationId,
                onProgressMessage: { progressMsg in
                    self.historyCoordinator.upsertToolExecutionMessage(progressMsg)
                }
            )

            // Append tool results to history
            for msg in toolResults {
                historyCoordinator.append(msg)
            }
        }

        // Final attempt after exhausting iterations
        let result = await aiInteractionCoordinator.sendMessageWithRetry(
            AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages,
                mediaAttachments: request.mediaAttachments,
                explicitContext: request.explicitContext,
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
        // Has planning language and numbered steps but no evidence of execution
        let hasPlanMarker = lower.contains("plan:") || lower.contains("**plan**") || lower.contains("# plan")
        let hasSteps = lower.contains("1.") || lower.contains("step 1") || lower.contains("step one")
        // But no tool call indicators (model said it would do something but didn't)
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

    private func appendRunSnapshot(payload: RunSnapshotPayload) async {
        await ToolLoopUtilities.appendRunSnapshot(payload: payload)
    }
}
