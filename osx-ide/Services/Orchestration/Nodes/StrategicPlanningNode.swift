import Foundation

@MainActor
struct StrategicPlanningNode: OrchestrationNode {
    static let idValue = "strategic_planning"

    let id: String = Self.idValue

    private let historyCoordinator: ChatHistoryCoordinator
    private let nextNodeId: String

    init(historyCoordinator: ChatHistoryCoordinator, nextNodeId: String) {
        self.historyCoordinator = historyCoordinator
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let plan = StrategicPlanSynthesizer.build(
            userInput: state.request.userInput,
            toolCalls: state.response?.toolCalls ?? []
        )

        await ConversationPlanStore.shared.set(conversationId: state.request.conversationId, plan: plan)

        historyCoordinator.append(ChatMessage(
            role: .assistant,
            content: plan
        ))

        return OrchestrationState(
            request: state.request,
            response: state.response,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }
}

private enum StrategicPlanSynthesizer {
    static func build(userInput: String, toolCalls: [AIToolCall]) -> String {
        let toolNames = Array(Set(toolCalls.map(\.name))).sorted()
        let toolLine = toolNames.isEmpty
            ? "- Execute changes using the appropriate tools"
            : "- Execute using: \(toolNames.joined(separator: ", "))"

        return """
        # Implementation Plan

        **Goal:** \(userInput)

        ## Strategy
        1. Identify target files and understand current structure
        2. Design minimal change set to satisfy the request
        3. Implement changes
        \(toolLine)
        4. Verify correctness and report completion
        """
    }
}
