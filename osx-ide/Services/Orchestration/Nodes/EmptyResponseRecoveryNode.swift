import Foundation

@MainActor
struct EmptyResponseRecoveryNode: OrchestrationNode {
    let id: String

    private let nextNodeId: String

    init(
        id: String,
        nextNodeId: String
    ) {
        self.id = id
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try requireResponse(from: state)

        let trimmed = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasToolCalls = (response.toolCalls?.isEmpty == false)
        guard trimmed.isEmpty, !hasToolCalls else {
            return OrchestrationState(
                request: request,
                response: response,
                lastToolResults: state.lastToolResults,
                branchExecution: state.branchExecution,
                transition: .next(nextNodeId)
            )
        }

        return OrchestrationState(
            request: request,
            response: AIServiceResponse(
                content: "I wasn't able to generate a final response. Please retry or clarify the next step.",
                toolCalls: nil
            ),
            lastToolResults: state.lastToolResults,
            branchExecution: state.branchExecution,
            transition: .next(nextNodeId)
        )
    }

    private func requireResponse(from state: OrchestrationState) throws -> AIServiceResponse {
        guard let response = state.response else {
            throw AppError.unknown("EmptyResponseRecoveryNode(\(id)): expected response to be set")
        }
        return response
    }
}
