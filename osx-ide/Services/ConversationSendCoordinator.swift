import Foundation

@MainActor
final class ConversationSendCoordinator {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let toolExecutionCoordinator: ToolExecutionCoordinator

    private let foldingHandler: ConversationFoldingHandler
    private let initialResponseHandler: InitialResponseHandler
    private let toolLoopHandler: ToolLoopHandler
    private let qaReviewHandler: QAReviewHandler
    private let reasoningCorrectionsHandler: ReasoningCorrectionsHandler
    private let finalResponseHandler: FinalResponseHandler

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        toolExecutionCoordinator: ToolExecutionCoordinator
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
        self.toolExecutionCoordinator = toolExecutionCoordinator

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
        self.reasoningCorrectionsHandler = ReasoningCorrectionsHandler(
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
            projectRoot: request.projectRoot
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
        await OrchestrationRunStore.shared.setProjectRoot(request.projectRoot)

        let graph = ConversationFlowGraphFactory.makeGraph(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            initialResponseHandler: initialResponseHandler,
            toolLoopHandler: toolLoopHandler,
            reasoningCorrectionsHandler: reasoningCorrectionsHandler,
            finalResponseHandler: finalResponseHandler,
            qaReviewHandler: qaReviewHandler
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

    private func appendRunSnapshot(payload: RunSnapshotPayload) async {
        await ToolLoopUtilities.appendRunSnapshot(payload: payload)
    }
}
