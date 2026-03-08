import Foundation

@MainActor
struct BranchReviewNode: OrchestrationNode {
    static let idValue = "branch_review"

    let id: String = Self.idValue

    private let executionNodeId: String
    private let finalNodeId: String

    init(executionNodeId: String, finalNodeId: String) {
        self.executionNodeId = executionNodeId
        self.finalNodeId = finalNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        guard let branchExecution = state.branchExecution else {
            return OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                transition: .next(finalNodeId)
            )
        }

        guard branchExecution.hasAdditionalBranches else {
            return OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                branchExecution: branchExecution,
                transition: .next(finalNodeId)
            )
        }

        return OrchestrationState(
            request: state.request,
            response: state.response,
            lastToolResults: [],
            branchExecution: branchExecution.advanced(),
            transition: .next(executionNodeId)
        )
    }
}
