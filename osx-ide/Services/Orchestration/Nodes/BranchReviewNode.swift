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
        return await shouldResumeExecutionForCurrentResponse(from: state)
    }

    private func shouldResumeExecutionForCurrentResponse(from state: OrchestrationState) async -> Bool {
        guard state.request.mode == .agent else { return false }
        guard let response = state.response else { return false }

        let content = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return false }

        let planMarkdown = await ConversationPlanStore.shared.get(
            conversationId: state.request.conversationId
        ) ?? ""
        let progress = PlanChecklistTracker.progress(in: planMarkdown)
        let hasIncompletePlan = progress.total > 0 && !progress.isComplete

        if hasIncompletePlan {
            return indicatesUnfinishedExecution(content)
        }

        if isIntermediateExecutionHandoff(content) {
            return false
        }

        guard !state.lastToolResults.isEmpty else { return false }
        guard response.toolCalls?.isEmpty ?? true else { return false }

        return indicatesUnfinishedExecution(content)
            || isSyntheticProgressArtifact(content)
            || ChatPromptBuilder.shouldForceToolFollowup(content: content)
            || ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: state.request.userInput,
                content: content,
                hasToolCalls: false
            )
    }

    private func indicatesUnfinishedExecution(_ content: String) -> Bool {
        let normalized = ChatPromptBuilder.contentForDisplay(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

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

    private func isSyntheticProgressArtifact(_ content: String) -> Bool {
        let normalized = ChatPromptBuilder.contentForDisplay(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        if normalized.contains("next: reviewing retrieved context and finalizing when the objective is satisfied") {
            return true
        }

        let generatedPrefixes = [
            "done -> next -> path:",
            "completed progress update for step ",
            "start checkpoint scan.",
            "checking checkpoints pass "
        ]
        return generatedPrefixes.contains { normalized.hasPrefix($0) }
    }

    private func isIntermediateExecutionHandoff(_ content: String) -> Bool {
        let normalized = ChatPromptBuilder.contentForDisplay(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let handoffSignals = [
            "done -> next -> path:",
            "continue with remaining",
            "continuing with the next",
            "starting execution now",
            "pending tasks remain"
        ]
        return handoffSignals.contains { normalized.contains($0) }
    }
}
