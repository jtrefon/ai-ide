import Foundation

@MainActor
struct ConditionalToolLoopNode: OrchestrationNode {
    let id: String

    private let handler: ToolLoopHandler
    private let nextNodeId: String
    private let toolLoopNodeId: String // Route back to tool loop if plan is incomplete

    init(id: String, handler: ToolLoopHandler, nextNodeId: String, toolLoopNodeId: String) {
        self.id = id
        self.handler = handler
        self.nextNodeId = nextNodeId
        self.toolLoopNodeId = toolLoopNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        if request.mode == .agent {
            let followupToolLoopResult = try await handler.handleToolLoopIfNeeded(
                response: response,
                explicitContext: request.explicitContext,
                mode: request.mode,
                projectRoot: request.projectRoot,
                conversationId: request.conversationId,
                availableTools: request.availableTools,
                cancelledToolCallIds: request.cancelledToolCallIds,
                runId: request.runId,
                userInput: request.userInput
            )

            // Check if plan is incomplete when response has no tool calls
            // If incomplete, force continuation by routing back to tool loop
            let shouldContinueLoop = await shouldRouteToToolLoop(
                conversationId: request.conversationId,
                response: followupToolLoopResult.response
            )
            
            let transitionNodeId = shouldContinueLoop ? toolLoopNodeId : nextNodeId
            
            if shouldContinueLoop {
                await AIToolTraceLogger.shared.log(type: "orchestration.plan_incomplete_reroute", data: [
                    "conversationId": request.conversationId,
                    "runId": request.runId,
                    "fromNode": id,
                    "toNode": toolLoopNodeId
                ])
            }

            return OrchestrationState(
                request: request,
                response: followupToolLoopResult.response,
                lastToolResults: followupToolLoopResult.lastToolResults,
                transition: .next(transitionNodeId)
            )
        }

        return OrchestrationState(
            request: request,
            response: response,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }

    private func shouldRouteToToolLoop(conversationId: String, response: AIServiceResponse) async -> Bool {
        // Only route back to tool loop if:
        // 1. Response has no tool calls (model stopped making tool calls)
        // 2. There is an incomplete plan
        guard response.toolCalls?.isEmpty ?? true else {
            return false
        }

        guard let plan = await ConversationPlanStore.shared.get(conversationId: conversationId),
              !plan.isEmpty else {
            return false
        }

        let progress = PlanChecklistTracker.progress(in: plan)
        
        // Route back to tool loop if plan is NOT complete
        return !progress.isComplete
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("ConditionalToolLoopNode(\(id)): expected response to be set")
        }
        return response
    }
}
