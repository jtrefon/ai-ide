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
        try await foldingHandler.foldIfNeeded(
            historyCoordinator: historyCoordinator,
            projectRoot: request.projectRoot
        )
        let response = try await executeConversationFlow(request)
        finalResponseHandler.appendFinalMessageAndLog(
            response: response,
            conversationId: request.conversationId,
            draftAssistantMessageId: request.draftAssistantMessageId
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
}
