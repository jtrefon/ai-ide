import Foundation

@MainActor
enum ConversationFlowGraphFactory {
    static func makeGraph(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        initialResponseHandler: InitialResponseHandler,
        toolLoopHandler: ToolLoopHandler,
        finalResponseHandler: FinalResponseHandler,
        qaReviewHandler: QAReviewHandler,
        qaReviewEnabled: Bool
    ) -> OrchestrationGraph {
        let strategicPlanningNodeId = StrategicPlanningNode.idValue
        let tacticalPlanningNodeId = TacticalPlanningNode.idValue
        let initialResponseNodeId = InitialResponseNode.idValue
        let emptyResponseRecoveryNodeId = "empty_response_recovery"
        let branchReviewNodeId = BranchReviewNode.idValue
        let finalResponseNextNodeId = qaReviewEnabled ? QAToolOutputReviewNode.idValue : nil

        return OrchestrationGraph(
            entryNodeId: strategicPlanningNodeId,
            nodes: [
                StrategicPlanningNode(
                    historyCoordinator: historyCoordinator,
                    nextNodeId: tacticalPlanningNodeId
                ),
                TacticalPlanningNode(
                    historyCoordinator: historyCoordinator,
                    nextNodeId: initialResponseNodeId
                ),
                InitialResponseNode(
                    historyCoordinator: historyCoordinator,
                    handler: initialResponseHandler,
                    nextNodeId: ToolLoopNode.idValue
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
                    executionNodeId: initialResponseNodeId,
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
