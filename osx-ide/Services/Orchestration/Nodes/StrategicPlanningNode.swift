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
        let existingPlan = await ConversationPlanStore.shared.get(conversationId: state.request.conversationId) ?? ""
        let progress = PlanChecklistTracker.progress(in: existingPlan)
        let shouldReuseExistingPlan = !existingPlan.isEmpty && progress.total > 0 && !progress.isComplete

        let plan: String
        if shouldReuseExistingPlan {
            plan = existingPlan
        } else {
            plan = StrategicPlanSynthesizer.build(
                userInput: state.request.userInput,
                toolCalls: state.response?.toolCalls ?? []
            )
        }

        await ConversationPlanStore.shared.set(conversationId: state.request.conversationId, plan: plan)
        upsertLatestPlanMessage(plan)

        return OrchestrationState(
            request: state.request,
            response: state.response,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }

    private func upsertLatestPlanMessage(_ plan: String) {
        let messages = historyCoordinator.messages
        if let lastPlanIndex = messages.lastIndex(where: {
            $0.role == .assistant && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# Implementation Plan")
        }) {
            historyCoordinator.replaceMessage(at: lastPlanIndex, with: ChatMessage(
                role: .assistant,
                content: plan
            ))
            return
        }

        historyCoordinator.append(ChatMessage(
            role: .assistant,
            content: plan
        ))
    }
}

private enum StrategicPlanSynthesizer {
    static func build(userInput: String, toolCalls: [AIToolCall]) -> String {
        let toolNames = Array(Set(toolCalls.map(\.name))).sorted()
        let toolLine = toolNames.isEmpty
            ? "- [ ] Execute changes using the appropriate tools"
            : "- [ ] Execute using: \(toolNames.joined(separator: ", "))"

        return """
        # Implementation Plan

        **Goal:** \(userInput)

        ## Strategy
        1. [ ] Identify target files and understand current structure
        2. [ ] Design minimal change set to satisfy the request
        3. [ ] Implement changes
        \(toolLine)
        4. [ ] Verify correctness and report completion
        """
    }
}
