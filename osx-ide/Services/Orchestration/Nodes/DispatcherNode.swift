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
        let response = try await handler.sendInitialResponse(
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            conversationId: request.conversationId,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        let hasToolCalls = !(response.toolCalls?.isEmpty ?? true)
        let nextNodeId = hasToolCalls ? toolLoopNodeId : finalResponseNodeId
        return state.transitioning(
            to: nextNodeId,
            response: response,
            lastToolResults: []
        )
    }
}
