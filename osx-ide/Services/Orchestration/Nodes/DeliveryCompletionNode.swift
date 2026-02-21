import Foundation

@MainActor
struct DeliveryCompletionNode: OrchestrationNode {
    let id: String

    private let handler: ReasoningCorrectionsHandler
    private let nextNodeId: String

    init(id: String, handler: ReasoningCorrectionsHandler, nextNodeId: String) {
        self.id = id
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        let gated = try await handler.enforceDeliveryCompletionIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput,
            conversationId: request.conversationId
        )

        return OrchestrationState(
            request: request,
            response: gated,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("DeliveryCompletionNode(\(id)): expected response to be set")
        }
        return response
    }
}
