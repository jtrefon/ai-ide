import Foundation

@available(*, deprecated, message: "Legacy branch execution system. PlanTool's structured TaskPlan is the replacement.")
protocol BranchExecutionContinuationDeciding: Sendable {
    func shouldResumeExecution(
        from state: OrchestrationState,
        branchExecution: OrchestrationState.BranchExecution
    ) async -> Bool
}

struct BranchExecutionContinuationDecider: BranchExecutionContinuationDeciding {
    private let planStore: any ConversationPlanStoring

    init(planStore: any ConversationPlanStoring = ConversationPlanStore.shared) {
        self.planStore = planStore
    }

    func shouldResumeExecution(
        from state: OrchestrationState,
        branchExecution: OrchestrationState.BranchExecution
    ) async -> Bool {
        guard !branchExecution.hasAdditionalBranches else { return false }
        guard state.response != nil else { return false }

        let signals = if let executionSignals = state.executionSignals {
            executionSignals
        } else {
            await OrchestrationExecutionSignalBuilder(planStore: planStore).build(for: state)
        }

        if state.request.mode != .agent {
            guard signals.hasToolResults else { return false }
            return signals.hasToolCalls
                || signals.shouldForceExecutionFollowup
                || signals.shouldForceToolFollowup
                || signals.indicatesUnfinishedExecution
        }

        if signals.hasIncompletePlan {
            return true
        }

        if signals.isIntermediateExecutionHandoff {
            return false
        }

        guard signals.hasToolResults else { return false }
        if signals.hasToolCalls {
            return true
        }

        return signals.deliveryState == .needsWork
            || signals.missingClaimedArtifacts
            || signals.isSyntheticProgressArtifact
            || signals.shouldForceToolFollowup
            || signals.shouldForceExecutionFollowup
    }
}
