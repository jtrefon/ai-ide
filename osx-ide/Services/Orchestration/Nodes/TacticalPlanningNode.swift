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

        let branchExecution = BranchExecutionPlanner.makeBranchExecution(
            tacticalPlan: unifiedPlan,
            userInput: state.request.userInput
        )

        return OrchestrationState(
            request: state.request,
            response: state.response,
            lastToolResults: state.lastToolResults,
            branchExecution: branchExecution,
            transition: .next(nextNodeId)
        )
    }
 }
