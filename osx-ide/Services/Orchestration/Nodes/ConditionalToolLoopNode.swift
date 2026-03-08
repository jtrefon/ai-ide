import Foundation

@MainActor
struct ConditionalToolLoopNode: OrchestrationNode {
    let id: String

    private let handler: ToolLoopHandler
    private let nextNodeId: String
    private let toolLoopNodeId: String

    init(id: String, handler: ToolLoopHandler, nextNodeId: String, toolLoopNodeId: String) {
        self.id = id
        self.handler = handler
        self.nextNodeId = nextNodeId
        self.toolLoopNodeId = toolLoopNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        _ = toolLoopNodeId
        let request = state.request
        let response = try requireResponse(from: state)

        // This node exists only to consume newly-emitted tool calls from prior gates.
        // If there are no tool calls, do not re-enter ToolLoopHandler (it can force
        // execution followups and create redundant cycles across orchestration phases).
        guard request.mode == .agent, response.toolCalls?.isEmpty == false else {
            return OrchestrationState(
                request: request,
                response: response,
                lastToolResults: state.lastToolResults,
                branchExecution: state.branchExecution,
                transition: .next(nextNodeId)
            )
        }

        let followupToolLoopResult = try await handler.handleToolLoopIfNeeded(
            response: response,
            explicitContext: state.effectiveExplicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            conversationId: request.conversationId,
            availableTools: request.availableTools,
            cancelledToolCallIds: request.cancelledToolCallIds,
            runId: request.runId,
            userInput: request.userInput
        )

        return OrchestrationState(
            request: request,
            response: followupToolLoopResult.response,
            lastToolResults: followupToolLoopResult.lastToolResults,
            branchExecution: state.branchExecution,
            transition: .next(nextNodeId)
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("ConditionalToolLoopNode(\(id)): expected response to be set")
        }
        return response
    }
}
