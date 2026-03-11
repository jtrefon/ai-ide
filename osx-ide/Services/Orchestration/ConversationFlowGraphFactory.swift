import Foundation

@MainActor
enum ConversationFlowGraphFactory {
    static func makeGraph(
        request: SendRequest,
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        initialResponseHandler: InitialResponseHandler,
        toolLoopHandler: ToolLoopHandler,
        finalResponseHandler: FinalResponseHandler,
        qaReviewHandler: QAReviewHandler,
        qaReviewEnabled: Bool
    ) -> OrchestrationGraph {
        _ = request
        let dispatcherNodeId = DispatcherNode.idValue
        let emptyResponseRecoveryNodeId = "empty_response_recovery"
        let branchReviewNodeId = BranchReviewNode.idValue
        let finalResponseNextNodeId = qaReviewEnabled ? QAToolOutputReviewNode.idValue : nil

        return OrchestrationGraph(
            entryNodeId: dispatcherNodeId,
            nodes: [
                DispatcherNode(
                    historyCoordinator: historyCoordinator,
                    handler: initialResponseHandler,
                    toolLoopNodeId: ToolLoopNode.idValue,
                    finalResponseNodeId: FinalResponseNode.idValue
                ),
                ToolLoopNode(
                    handler: toolLoopHandler,
                    nextNodeId: emptyResponseRecoveryNodeId
                ),
                EmptyResponseRecoveryNode(
                    id: emptyResponseRecoveryNodeId,
                    nextNodeId: branchReviewNodeId,
                ),
                BranchReviewNode(
                    executionNodeId: ToolLoopNode.idValue,
                    finalNodeId: FinalResponseNode.idValue
                ),
                FinalResponseNode(
                    handler: finalResponseHandler,
                    nextNodeId: finalResponseNextNodeId
                ),
            ] + qaReviewNodes(handler: qaReviewHandler, enabled: qaReviewEnabled)
        )
    }

    private static func qaReviewNodes(handler: QAReviewHandler, enabled: Bool) -> [any OrchestrationNode] {
        guard enabled else { return [] }

        return [
            QAToolOutputReviewNode(
                handler: handler,
                nextNodeId: QAQualityReviewNode.idValue
            ),
            QAQualityReviewNode(handler: handler)
        ]
    }
}
