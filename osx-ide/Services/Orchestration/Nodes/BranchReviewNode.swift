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
            let signals = if let executionSignals = state.executionSignals {
                executionSignals
            } else {
                await OrchestrationExecutionSignalBuilder().build(for: state)
            }

            var shouldRetry = signals.hasToolCalls
                || signals.missingClaimedArtifacts

            if !shouldRetry, signals.indicatesUnfinishedExecution, state.executionCycleCount < ToolLoopConstants.maxNeedsWorkReentries,
               signals.planProgress.hasChecklist {
                // Allow a limited number of re-entries when the model explicitly signals
                // unfinished work AND there is a plan with a checklist to guide the next
                // execution cycle. Capped to prevent infinite graph-level cycles.
                shouldRetry = true
            }

            if shouldRetry {
                if state.executionCycleCount >= ToolLoopConstants.maxExecutionCycles {
                    await AIToolTraceLogger.shared.log(type: "chat.branch_review_cycle_limit_reached", data: [
                        "runId": state.request.runId,
                        "executionCycleCount": state.executionCycleCount,
                        "hasToolCalls": signals.hasToolCalls,
                        "hasIncompletePlan": signals.hasIncompletePlan
                    ])
                    return state.transitioning(to: finalNodeId, executionSignals: signals)
                }
                return state.transitioning(to: executionNodeId, executionSignals: signals)
                    .incrementingExecutionCycle()
            }

            return state.transitioning(to: finalNodeId, executionSignals: signals)
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

        let hasToolCalls = !(state.response?.toolCalls?.isEmpty ?? true)
        let hasContent = !(state.response?.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasToolCalls && hasContent && !branchExecution.hasAdditionalBranches {
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
