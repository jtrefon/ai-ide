import Foundation

@MainActor
struct StrategicPlanningNode: OrchestrationNode {
    static let idValue = "strategic_planning"

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
        let shouldReuseExistingPlan = !existingPlan.isEmpty && progress.total > 0 && !progress.isComplete

        let plan: String
        if shouldReuseExistingPlan {
            plan = existingPlan
        } else {
            plan = StrategicPlanSynthesizer.build(userInput: state.request.userInput)
        }

        await planStore.set(conversationId: state.request.conversationId, plan: plan)
        return state.transitioning(to: nextNodeId)
    }
}
