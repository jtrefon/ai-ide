import Foundation

@MainActor
struct TacticalPlanningNode: OrchestrationNode {
    static let idValue = "tactical_planning"

    let id: String = Self.idValue

    private let nextNodeId: String
    private let planStore: any ConversationPlanStoring

    init(nextNodeId: String, planStore: any ConversationPlanStoring = ConversationPlanStore.shared) {
        self.nextNodeId = nextNodeId
        self.planStore = planStore
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let planningMode = AgentPlanningPolicy().planningMode(
            userInput: state.request.userInput,
            mode: state.request.mode,
            availableToolsCount: state.request.availableTools.count
        )
        guard planningMode == .requirePlanning else {
            return state.transitioning(to: nextNodeId)
        }

        let existingPlan = await planStore.get(conversationId: state.request.conversationId) ?? ""
        let progress = PlanChecklistTracker.progress(in: existingPlan)
        let shouldPreserveCurrentPlan = !existingPlan.isEmpty && progress.total > 0 && !progress.isComplete

        let unifiedPlan = await TacticalPlanSynthesizer.mergeIntoStrategicPlan(
            strategicPlan: existingPlan,
            userInput: state.request.userInput,
            preserveCurrentPlan: shouldPreserveCurrentPlan
        )

        await planStore.set(
            conversationId: state.request.conversationId,
            plan: unifiedPlan
        )

        let branchExecution = BranchExecutionPlanner.makeBranchExecution(
            tacticalPlan: unifiedPlan,
            userInput: state.request.userInput
        )

        return state.transitioning(
            to: nextNodeId,
            branchExecution: branchExecution,
        )
    }
}
