import Foundation

@MainActor
struct TacticalPlanningNode: OrchestrationNode {
    static let idValue = "tactical_planning"

    let id: String = Self.idValue

    private let historyCoordinator: ChatHistoryCoordinator
    private let nextNodeId: String

    init(historyCoordinator: ChatHistoryCoordinator, nextNodeId: String) {
        self.historyCoordinator = historyCoordinator
        self.nextNodeId = nextNodeId
    }

    func run(state: OrchestrationState) async throws -> OrchestrationState {
        let existingPlan = await ConversationPlanStore.shared.get(conversationId: state.request.conversationId) ?? ""
        let tacticalPlan = TacticalPlanSynthesizer.build(from: existingPlan)

        await ConversationPlanStore.shared.set(
            conversationId: state.request.conversationId,
            plan: [existingPlan, tacticalPlan]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        )

        historyCoordinator.append(ChatMessage(
            role: .assistant,
            content: "Progress update: tactical execution plan prepared."
        ))

        historyCoordinator.append(ChatMessage(
            role: .assistant,
            content: tacticalPlan
        ))

        return OrchestrationState(
            request: state.request,
            response: state.response,
            lastToolResults: state.lastToolResults,
            transition: .next(nextNodeId)
        )
    }
}

private enum TacticalPlanSynthesizer {
    static func build(from strategicPlan: String) -> String {
        let bullets = strategicPlan
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard let first = line.first else { return false }
                return first.isNumber
            }
            .prefix(3)

        let steps: [String]
        if bullets.isEmpty {
            steps = [
                "Inspect impacted files and gather evidence.",
                "Apply smallest safe implementation changes.",
                "Run validations and summarize outcomes."
            ]
        } else {
            steps = bullets.map { line in
                "Execute: \(line)"
            }
        }

        let renderedSteps = steps.enumerated().map { index, step in
            "\(index + 1). \(step)"
        }.joined(separator: "\n")

        return """
        ## Tactical Plan

        \(renderedSteps)
        """
    }
}
