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

        let existingPlan = await planStore.getPlan(conversationId: state.request.conversationId)
        let shouldReuse = existingPlan != nil && !existingPlan!.isComplete

        if shouldReuse {
            return state.transitioning(to: nextNodeId)
        }

        // Generate a new structured plan
        let plan = StrategicPlanSynthesizer.buildStructured(userInput: state.request.userInput, mode: state.request.mode)
        await planStore.setPlan(conversationId: state.request.conversationId, plan: plan)
        return state.transitioning(to: nextNodeId)
    }
}
