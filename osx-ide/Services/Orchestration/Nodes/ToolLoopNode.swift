import Foundation

@MainActor
struct ToolLoopNode: OrchestrationNode {
    static let idValue = "tool_loop"

    let id: String = Self.idValue

    private let handler: ToolLoopHandler
    private let nextNodeId: String

    init(handler: ToolLoopHandler, nextNodeId: String) {
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        let toolLoopResult = try await handler.handleToolLoopIfNeeded(
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

        var nextState = state.transitioning(
            to: nextNodeId,
            response: toolLoopResult.response,
            lastToolResults: toolLoopResult.lastToolResults
        )
        nextState = nextState.updating(
            executionSignals: await OrchestrationExecutionSignalBuilder().build(for: nextState)
        )
        return nextState
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("ToolLoopNode: expected response to be set")
        }
        return response
    }
}
