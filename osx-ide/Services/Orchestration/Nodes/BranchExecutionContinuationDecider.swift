import Foundation

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
        guard state.request.mode == .agent else { return false }
        guard !branchExecution.hasAdditionalBranches else { return false }
        guard let response = state.response else { return false }

        let signals = if let executionSignals = state.executionSignals {
            executionSignals
        } else {
            await OrchestrationExecutionSignalBuilder(planStore: planStore).build(for: state)
        }

        if signals.hasIncompletePlan {
            if signals.hasToolCalls {
                return true
            }

            if signals.hasToolResults {
                return signals.deliveryState != .done
                    || signals.missingClaimedArtifacts
                    || signals.shouldForceExecutionFollowup
                    || signals.indicatesUnfinishedExecution
                    || signals.isSyntheticProgressArtifact
            }

            return signals.deliveryState == .needsWork || signals.indicatesUnfinishedExecution
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
