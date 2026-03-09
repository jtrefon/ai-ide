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

        if await shouldResumeExecution(from: state, branchExecution: branchExecution) {
            return OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                branchExecution: state.branchExecution,
                transition: .next(executionNodeId)
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

    private func shouldResumeExecution(
        from state: OrchestrationState,
        branchExecution: OrchestrationState.BranchExecution
    ) async -> Bool {
        guard state.request.mode == .agent else { return false }
        guard !branchExecution.hasAdditionalBranches else { return false }
        guard let response = state.response else { return false }

        let planMarkdown = await ConversationPlanStore.shared.get(
            conversationId: state.request.conversationId
        ) ?? ""
        let progress = PlanChecklistTracker.progress(in: planMarkdown)
        guard progress.total > 0, !progress.isComplete else { return false }

        let content = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return false }

        let normalized = content.lowercased()
        let unfinishedSignals = [
            "needs_work",
            "needs work",
            "pending tasks remain",
            "continue with remaining",
            "continuing with the next",
            "remaining implementation",
            "done -> next -> path:"
        ]

        if unfinishedSignals.contains(where: { normalized.contains($0) }) {
            return true
        }

        return ChatPromptBuilder.deliveryStatus(from: content) == .needsWork
    }
}
