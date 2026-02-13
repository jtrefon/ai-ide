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
            content: "Progress update: strategic plan prepared."
        ))

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
        let toolLine: String
        if toolNames.isEmpty {
            toolLine = "4. Execute with the minimal safe toolset needed by findings."
        } else {
            toolLine = "4. Execute using these tools first: \(toolNames.joined(separator: ", "))."
        }

        return """
        # Strategic Plan

        1. Clarify the requested outcome: \(userInput)
        2. Identify relevant files, symbols, and constraints.
        3. Design the smallest safe change set that satisfies the request.
        \(toolLine)
        5. Validate behavior and summarize delivery status.
        """
    }
}
