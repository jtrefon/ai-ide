import Foundation

@MainActor
enum ConversationFlowGraphFactory {
    static func makeGraph(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator,
        initialResponseHandler: InitialResponseHandler,
        toolLoopHandler: ToolLoopHandler,
        reasoningCorrectionsHandler: ReasoningCorrectionsHandler,
        finalResponseHandler: FinalResponseHandler,
        qaReviewHandler: QAReviewHandler
    ) -> OrchestrationGraph {
        let strategicPlanningNodeId = StrategicPlanningNode.idValue
        let tacticalPlanningNodeId = TacticalPlanningNode.idValue
        let toolLoopAfterReasoningNodeId = "tool_loop_after_reasoning"
        let toolLoopAfterDeliveryGateNodeId = "tool_loop_after_delivery_gate"
        let toolLoopAfterFinalDeliveryNodeId = "tool_loop_after_final_delivery"
        let emptyResponseRecoveryNodeId = "empty_response_recovery"
        let finalDeliveryCompletionNodeId = "final_delivery_completion"
        let postFinalReasoningCorrectionsNodeId = "post_final_reasoning_corrections"

        return OrchestrationGraph(
            entryNodeId: InitialResponseNode.idValue,
            nodes: [
                InitialResponseNode(
                    historyCoordinator: historyCoordinator,
                    handler: initialResponseHandler,
                    nextNodeId: strategicPlanningNodeId
                ),
                StrategicPlanningNode(
                    historyCoordinator: historyCoordinator,
                    nextNodeId: tacticalPlanningNodeId
                ),
                TacticalPlanningNode(
                    historyCoordinator: historyCoordinator,
                    nextNodeId: ToolLoopNode.idValue
                ),
                ToolLoopNode(
                    handler: toolLoopHandler,
                    nextNodeId: ReasoningCorrectionsNode.idValue
                ),
                ReasoningCorrectionsNode(
                    handler: reasoningCorrectionsHandler,
                    nextNodeId: toolLoopAfterReasoningNodeId
                ),
                ConditionalToolLoopNode(
                    id: toolLoopAfterReasoningNodeId,
                    handler: toolLoopHandler,
                    nextNodeId: DeliveryGateNode.idValue,
                    toolLoopNodeId: ToolLoopNode.idValue
                ),
                DeliveryGateNode(
                    historyCoordinator: historyCoordinator,
                    handler: reasoningCorrectionsHandler,
                    nextNodeId: toolLoopAfterDeliveryGateNodeId
                ),
                ConditionalToolLoopNode(
                    id: toolLoopAfterDeliveryGateNodeId,
                    handler: toolLoopHandler,
                    nextNodeId: emptyResponseRecoveryNodeId,
                    toolLoopNodeId: ToolLoopNode.idValue
                ),
                EmptyResponseRecoveryNode(
                    id: emptyResponseRecoveryNodeId,
                    historyCoordinator: historyCoordinator,
                    aiInteractionCoordinator: aiInteractionCoordinator,
                    toolLoopHandler: toolLoopHandler,
                    nextNodeId: finalDeliveryCompletionNodeId
                ),
                DeliveryCompletionNode(
                    id: finalDeliveryCompletionNodeId,
                    handler: reasoningCorrectionsHandler,
                    nextNodeId: toolLoopAfterFinalDeliveryNodeId
                ),
                ConditionalToolLoopNode(
                    id: toolLoopAfterFinalDeliveryNodeId,
                    handler: toolLoopHandler,
                    nextNodeId: FinalResponseNode.idValue,
                    toolLoopNodeId: ToolLoopNode.idValue
                ),
                FinalResponseNode(
                    handler: finalResponseHandler,
                    nextNodeId: postFinalReasoningCorrectionsNodeId
                ),
                PostFinalReasoningCorrectionsNode(
                    id: postFinalReasoningCorrectionsNodeId,
                    handler: reasoningCorrectionsHandler,
                    nextNodeId: QAToolOutputReviewNode.idValue
                ),
                QAToolOutputReviewNode(
                    handler: qaReviewHandler,
                    nextNodeId: QAQualityReviewNode.idValue
                ),
                QAQualityReviewNode(handler: qaReviewHandler)
            ]
        )
    }
}
