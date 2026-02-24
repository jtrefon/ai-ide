import Foundation

@MainActor
struct QAQualityReviewNode: OrchestrationNode {
    static let idValue = "qa_quality_review"

    let id: String = Self.idValue

    private let handler: QAReviewHandler

    init(handler: QAReviewHandler) {
        self.handler = handler
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        let reviewed = try await handler.performQualityReviewIfNeeded(
            response: response,
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            qaReviewEnabled: request.qaReviewEnabled,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        return OrchestrationState(
            request: request,
            response: reviewed,
            lastToolResults: state.lastToolResults,
            transition: .end
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("QAQualityReviewNode: expected response to be set")
        }
        return response
    }
}
