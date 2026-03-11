import Foundation

@MainActor
struct StrategicPlanningNode: OrchestrationNode {
    static let idValue = "strategic_planning"

    let id: String = Self.idValue

    private let historyCoordinator: ChatHistoryCoordinator
    private let nextNodeId: String

    init(historyCoordinator: ChatHistoryCoordinator, nextNodeId: String) {
        self.historyCoordinator = historyCoordinator
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let planningMode = AgentPlanningPolicy().planningMode(
            userInput: state.request.userInput,
            mode: state.request.mode,
            availableToolsCount: state.request.availableTools.count
        )
        guard planningMode == .requirePlanning else {
            return OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                branchExecution: state.branchExecution,
                transition: .next(nextNodeId)
            )
        }

        let existingPlan = await ConversationPlanStore.shared.get(conversationId: state.request.conversationId) ?? ""
        let progress = PlanChecklistTracker.progress(in: existingPlan)
        let shouldReuseExistingPlan = !existingPlan.isEmpty && progress.total > 0 && !progress.isComplete

        let plan: String
        if shouldReuseExistingPlan {
            plan = existingPlan
        } else {
            plan = StrategicPlanSynthesizer.build(userInput: state.request.userInput)
        }

        await ConversationPlanStore.shared.set(conversationId: state.request.conversationId, plan: plan)

        return OrchestrationState(
            request: state.request,
            response: state.response,
            lastToolResults: state.lastToolResults,
            branchExecution: state.branchExecution,
            transition: .next(nextNodeId)
        )
    }
}
