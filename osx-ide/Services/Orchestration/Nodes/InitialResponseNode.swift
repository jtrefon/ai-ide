import Foundation

@MainActor
struct InitialResponseNode: OrchestrationNode {
    static let idValue = "initial_response"

    let id: String = Self.idValue

    private let historyCoordinator: ChatHistoryCoordinator
    private let handler: InitialResponseHandler
    private let nextNodeId: String

    init(historyCoordinator: ChatHistoryCoordinator, handler: InitialResponseHandler, nextNodeId: String) {
        self.historyCoordinator = historyCoordinator
        self.handler = handler
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let request = state.request
        let response = try await handler.sendInitialResponse(
            explicitContext: request.explicitContext,
            mode: request.mode,
            projectRoot: request.projectRoot,
            availableTools: request.availableTools,
            runId: request.runId,
            userInput: request.userInput
        )

        let hasToolCalls = !(response.toolCalls?.isEmpty ?? true)
        if !hasToolCalls, let content = response.content,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let split = ChatPromptBuilder.splitReasoning(from: content)
            historyCoordinator.append(ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning)
            ))
        }

        return OrchestrationState(
            request: request,
            response: response,
            lastToolResults: [],
            transition: .next(nextNodeId)
        )
    }
}
