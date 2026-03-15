import Foundation

struct OrchestrationExecutionSignalBuilder {
    private let planStore: any ConversationPlanStoring

    init(planStore: any ConversationPlanStoring = ConversationPlanStore.shared) {
        self.planStore = planStore
    }

    func build(for state: OrchestrationState) async -> OrchestrationState.ExecutionSignals {
        let content = state.response?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasToolCalls = !(state.response?.toolCalls?.isEmpty ?? true)
        let hasToolResults = !state.lastToolResults.isEmpty

        let deliveryState: OrchestrationState.ExecutionSignals.DeliveryState
        switch ChatPromptBuilder.deliveryStatus(from: content) {
        case .done:
            deliveryState = .done
        case .needsWork:
            deliveryState = .needsWork
        case .none:
            deliveryState = .missing
        }

        let planMarkdown = await planStore.get(conversationId: state.request.conversationId) ?? ""
        let progress = PlanChecklistTracker.progress(in: planMarkdown)
        let planProgress = OrchestrationState.ExecutionSignals.PlanProgress(
            completed: progress.completed,
            total: progress.total
        )

        let missingClaimedArtifacts = !content.isEmpty && ChatPromptBuilder.hasMissingClaimedFileArtifacts(
            content: content,
            projectRoot: state.request.projectRoot
        )
        let shouldForceExecutionFollowup = !content.isEmpty && ChatPromptBuilder.shouldForceExecutionFollowup(
            userInput: state.request.userInput,
            content: content,
            hasToolCalls: hasToolCalls
        )
        let shouldForceToolFollowup = !content.isEmpty && ChatPromptBuilder.shouldForceToolFollowup(content: content)

        return OrchestrationState.ExecutionSignals(
            hasToolCalls: hasToolCalls,
            hasToolResults: hasToolResults,
            deliveryState: deliveryState,
            planProgress: planProgress,
            missingClaimedArtifacts: missingClaimedArtifacts,
            shouldForceExecutionFollowup: shouldForceExecutionFollowup,
            shouldForceToolFollowup: shouldForceToolFollowup,
            indicatesUnfinishedExecution: indicatesUnfinishedExecution(content),
            isIntermediateExecutionHandoff: isIntermediateExecutionHandoff(content),
            isSyntheticProgressArtifact: isSyntheticProgressArtifact(content)
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
            "done → next → path:",
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
