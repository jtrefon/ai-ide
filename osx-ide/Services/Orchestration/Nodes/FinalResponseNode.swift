import Foundation

@MainActor
struct FinalResponseNode: OrchestrationNode {
    static let idValue = "final_response"

    let id: String = Self.idValue

    private let handler: FinalResponseHandler
    private let nextNodeId: String?

    init(handler: FinalResponseHandler, nextNodeId: String?) {
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        let final = try await handler.requestFinalResponseIfNeeded(
            response: response,
            explicitContext: state.effectiveExplicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            toolResults: state.lastToolResults,
            runId: request.runId,
            conversationId: request.conversationId
        )

        return OrchestrationState(
            request: request,
            response: final,
            lastToolResults: state.lastToolResults,
            branchExecution: state.branchExecution,
            transition: nextNodeId.map { .next($0) } ?? .end
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("FinalResponseNode: expected response to be set")
        }
        return response
    }
}
