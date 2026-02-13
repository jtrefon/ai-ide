import Foundation

@MainActor
struct ConditionalToolLoopNode: OrchestrationNode {
    let id: String

    private let handler: ToolLoopHandler
    private let nextNodeId: String

    init(id: String, handler: ToolLoopHandler, nextNodeId: String) {
        self.id = id
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        if request.mode == .agent, response.toolCalls?.isEmpty == false {
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

            return OrchestrationState(
                request: request,
                response: followupToolLoopResult.response,
                lastToolResults: followupToolLoopResult.lastToolResults,
                transition: .next(nextNodeId)
            )
        }

        return OrchestrationState(
            request: request,
            response: response,
            lastToolResults: state.lastToolResults,
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
