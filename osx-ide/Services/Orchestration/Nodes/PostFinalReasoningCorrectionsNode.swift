import Foundation

@MainActor
struct PostFinalReasoningCorrectionsNode: OrchestrationNode {
    let id: String

    private let handler: ReasoningCorrectionsHandler
    private let nextNodeId: String?

    init(id: String, handler: ReasoningCorrectionsHandler, nextNodeId: String?) {
        self.id = id
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
            transition: nextNodeId.map { .next($0) } ?? .end
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown(
                "PostFinalReasoningCorrectionsNode(\(id)): expected response to be set")
        }
        return response
    }
}
