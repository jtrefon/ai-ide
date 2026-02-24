import Foundation

@MainActor
struct TacticalPlanningNode: OrchestrationNode {
    static let idValue = "tactical_planning"

    let id: String = Self.idValue

    private let historyCoordinator: ChatHistoryCoordinator
    private let nextNodeId: String

    init(historyCoordinator: ChatHistoryCoordinator, nextNodeId: String) {
        self.historyCoordinator = historyCoordinator
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let existingPlan = await ConversationPlanStore.shared.get(conversationId: state.request.conversationId) ?? ""
        let progress = PlanChecklistTracker.progress(in: existingPlan)
        let shouldPreserveCurrentPlan = !existingPlan.isEmpty && progress.total > 0 && !progress.isComplete

        let unifiedPlan = await TacticalPlanSynthesizer.mergeIntoStrategicPlan(
            strategicPlan: existingPlan,
            userInput: state.request.userInput,
            preserveCurrentPlan: shouldPreserveCurrentPlan
        )

        await ConversationPlanStore.shared.set(
            conversationId: state.request.conversationId,
            plan: unifiedPlan
        )

        updateLatestPlanMessage(with: unifiedPlan)

        return OrchestrationState(
            request: state.request,
            response: state.response,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }

    private func updateLatestPlanMessage(with plan: String) {
        let messages = historyCoordinator.messages
        if let lastPlanIndex = messages.lastIndex(where: {
            $0.role == .assistant && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# Implementation Plan")
        }) {
            historyCoordinator.replaceMessage(at: lastPlanIndex, with: ChatMessage(
                role: .assistant,
                content: plan
            ))
        } else {
            historyCoordinator.append(ChatMessage(
                role: .assistant,
                content: plan
            ))
        }
    }
}
