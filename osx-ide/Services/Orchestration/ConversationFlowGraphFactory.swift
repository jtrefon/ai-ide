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
        let dispatcherNodeId = DispatcherNode.idValue
        let toolLoopNodeId = ToolLoopNode.idValue
        let finalResponseNodeId = FinalResponseNode.idValue
        let postFinalReasoningCorrectionsNodeId = "post_final_reasoning_corrections"

        return OrchestrationGraph(
            entryNodeId: dispatcherNodeId,
            nodes: [
                DispatcherNode(
                    historyCoordinator: historyCoordinator,
                    handler: initialResponseHandler,
                    toolLoopNodeId: toolLoopNodeId,
                    finalResponseNodeId: finalResponseNodeId
                ),
                ToolLoopNode(
                    handler: toolLoopHandler,
                    nextNodeId: dispatcherNodeId  // Loop back to dispatcher for next turn/eval
                ),
                FinalResponseNode(
                    handler: finalResponseHandler,
                    nextNodeId: postFinalReasoningCorrectionsNodeId
                ),
                PostFinalReasoningCorrectionsNode(
                    id: postFinalReasoningCorrectionsNodeId,
                    handler: reasoningCorrectionsHandler,
                    nextNodeId: nil  // End after corrections for now, or route to QA
                ),
            ]
        )
    }
}
