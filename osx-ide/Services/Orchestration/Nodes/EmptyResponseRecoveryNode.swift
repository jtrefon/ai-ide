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
        let response = try requireResponse(from: state)

        let trimmed = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasToolCalls = (response.toolCalls?.isEmpty == false)
        guard trimmed.isEmpty, !hasToolCalls else {
            var nextState = state.transitioning(to: nextNodeId, response: response)
            nextState = nextState.updating(
                executionSignals: await OrchestrationExecutionSignalBuilder().build(for: nextState)
            )
            return nextState
        }

        var nextState = state.transitioning(
            to: nextNodeId,
            response: AIServiceResponse(
                content: "Your previous turn produced no response. Per your operating contract, end the turn with either a tool call or a short Reflection (what you produced, what remains against the request, next action) and a `Delivery: done|needs_work` state — then continue. What is the next concrete action toward the requested deliverables?",
                toolCalls: nil
            )
        )
        nextState = nextState.updating(
            executionSignals: await OrchestrationExecutionSignalBuilder().build(for: nextState)
        )
        return nextState
    }

}
