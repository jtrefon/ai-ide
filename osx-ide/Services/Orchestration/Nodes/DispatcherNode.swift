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
        let response = try await handler.sendInitialResponse(            mode: request.mode,
            projectRoot: request.projectRoot,
            conversationId: request.conversationId,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        let hasToolCalls = !(response.toolCalls?.isEmpty ?? true)
        let signals = await OrchestrationExecutionSignalBuilder().build(for: state.updating(response: response))
        
        let nextNodeId: String
        var updatedState = state.updating(response: response, executionSignals: signals)
        
        if hasToolCalls {
            nextNodeId = toolLoopNodeId
            updatedState = updatedState.resettingThinkingTurns()
        } else if signals.deliveryState == .needsWork && signals.planProgress.hasChecklist && state.thinkingTurnsCount < 2 {
            // Self-correction: model says it needs work AND we have a plan context - retry tool loop
            nextNodeId = toolLoopNodeId
            updatedState = updatedState.incrementingThinkingTurns().incrementingExecutionCycle()
        } else if signals.shouldForceToolFollowup || signals.shouldForceExecutionFollowup {
            // Model indicated intent to use tools or execute actions but failed to emit actual tool calls
            nextNodeId = toolLoopNodeId
            updatedState = updatedState.incrementingThinkingTurns().incrementingExecutionCycle()
        } else {
            nextNodeId = finalResponseNodeId
            updatedState = updatedState.resettingThinkingTurns()
        }
        
        return updatedState.transitioning(
            to: nextNodeId,
            lastToolResults: []
        )
    }
}
