import Foundation

@MainActor
struct QAToolOutputReviewNode: OrchestrationNode {
    static let idValue = "qa_tool_output_review"

    let id: String = Self.idValue

    private let handler: QAReviewHandler
    private let nextNodeId: String

    init(handler: QAReviewHandler, nextNodeId: String) {
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        let reviewed = try await handler.performToolOutputReviewIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            qaReviewEnabled: request.qaReviewEnabled,
            availableTools: request.availableTools,
            toolResults: state.lastToolResults,
            runId: request.runId,
            userInput: request.userInput
        )

        return OrchestrationState(
            request: request,
            response: reviewed,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("QAToolOutputReviewNode: expected response to be set")
        }
        return response
    }
}
