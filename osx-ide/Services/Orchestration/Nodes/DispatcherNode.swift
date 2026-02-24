import Foundation

/// The central entry point for the tool-driven orchestration loop.
/// Based on the LLM's response, it decides whether to proceed to tool execution
/// or terminate the loop with a final response.
@MainActor
struct DispatcherNode: OrchestrationNode {
    static let idValue = "dispatcher"

    let id: String = Self.idValue

    private let historyCoordinator: ChatHistoryCoordinator
    private let handler: InitialResponseHandler
    private let toolLoopNodeId: String
    private let finalResponseNodeId: String

    init(
        historyCoordinator: ChatHistoryCoordinator,
        handler: InitialResponseHandler,
        toolLoopNodeId: String,
        finalResponseNodeId: String
    ) {
        self.historyCoordinator = historyCoordinator
        self.handler = handler
        self.toolLoopNodeId = toolLoopNodeId
        self.finalResponseNodeId = finalResponseNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request

        // Use the existing handler logic for consistency (including retry loops if any)
        let response = try await handler.sendInitialResponse(
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        let hasToolCalls = !(response.toolCalls?.isEmpty ?? true)

        // Determine next transition
        let nextNodeId = hasToolCalls ? toolLoopNodeId : finalResponseNodeId

        return OrchestrationState(
            request: request,
            response: response,
            lastToolResults: [],
            transition: .next(nextNodeId)
        )
    }
}
