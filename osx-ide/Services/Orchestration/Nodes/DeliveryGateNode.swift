import Foundation

@MainActor
struct DeliveryGateNode: OrchestrationNode {
    static let idValue = "delivery_gate"

    let id: String = Self.idValue

    private let historyCoordinator: ChatHistoryCoordinator
    private let handler: ReasoningCorrectionsHandler
    private let nextNodeId: String

    init(historyCoordinator: ChatHistoryCoordinator, handler: ReasoningCorrectionsHandler, nextNodeId: String) {
        self.historyCoordinator = historyCoordinator
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        _ = historyCoordinator
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
            throw AppError.unknown("DeliveryGateNode: expected response to be set")
        }
        return response
    }
}
