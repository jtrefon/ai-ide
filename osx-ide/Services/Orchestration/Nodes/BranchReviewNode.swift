import Foundation

@MainActor
struct BranchReviewNode: OrchestrationNode {
    static let idValue = "branch_review"

    let id: String = Self.idValue

    private let executionNodeId: String
    private let finalNodeId: String
    private let continuationDecider: any BranchExecutionContinuationDeciding

    init(
        executionNodeId: String,
        finalNodeId: String,
        continuationDecider: any BranchExecutionContinuationDeciding = BranchExecutionContinuationDecider()
    ) {
        self.executionNodeId = executionNodeId
        self.finalNodeId = finalNodeId
        self.continuationDecider = continuationDecider
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        guard let branchExecution = state.branchExecution else {
            return state.transitioning(to: finalNodeId)
        }

        if await continuationDecider.shouldResumeExecution(
            from: state,
            branchExecution: branchExecution
        ) {
            return state.transitioning(to: executionNodeId)
        }

        guard branchExecution.hasAdditionalBranches else {
            return state.transitioning(
                to: finalNodeId,
                branchExecution: branchExecution
            )
        }

        return state.transitioning(
            to: executionNodeId,
            lastToolResults: [],
            branchExecution: branchExecution.advanced()
        )
    }
}
