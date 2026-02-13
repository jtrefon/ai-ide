import Foundation

@MainActor
struct ReasoningCorrectionsNode: OrchestrationNode {
    static let idValue = "reasoning_corrections"

    let id: String = Self.idValue

    private let handler: ReasoningCorrectionsHandler
    private let nextNodeId: String

    init(handler: ReasoningCorrectionsHandler, nextNodeId: String) {
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        let corrected = try await handler.applyReasoningCorrectionsIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId
        )

        return OrchestrationState(
            request: request,
            response: corrected,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("ReasoningCorrectionsNode: expected response to be set")
        }
        return response
    }
}
