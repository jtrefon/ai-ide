import Foundation

struct AgentPlanningPolicy {
    enum PlanningMode: Sendable {
        case skipPlanning
        case requirePlanning
    }

    func planningMode(
        userInput: String,
        mode: AIMode,
        availableToolsCount: Int
    ) -> PlanningMode {
        guard mode == .agent else { return .skipPlanning }
        guard shouldPlan(userInput: userInput, availableToolsCount: availableToolsCount) else {
            return .skipPlanning
        }
        return .requirePlanning
    }

    private func shouldPlan(userInput: String, availableToolsCount: Int) -> Bool {
        let normalized = userInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return false }

        if looksInformational(normalized) {
            return false
        }

        if availableToolsCount == 0 {
            return false
        }

        if looksComplex(normalized) {
            return true
        }

        return false
    }

    private func looksInformational(_ normalized: String) -> Bool {
        let informationalPrefixes = [
            "what",
            "is",
            "are",
            "does",
            "do",
            "did",
            "can you explain",
            "could you explain",
            "tell me",
            "describe",
            "why",
            "how does",
            "status",
            "check whether",
            "is that finished",
            "is that complete"
        ]

        if informationalPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        let informationalPhrases = [
            "is it finished",
            "is it complete",
            "what about",
            "finished, complete",
            "is that finished",
            "is that complete"
        ]

        return informationalPhrases.contains(where: { normalized.contains($0) })
    }

    private func looksComplex(_ normalized: String) -> Bool {
        let complexitySignals = [
            " and ",
            " then ",
            " after that ",
            "step by step",
            "plan",
            "multiple files",
            "across",
            "refactor",
            "migrate",
            "architecture",
            "re-architect",
            "long-running",
            "complex",
            "full",
            "comprehensive"
        ]

        if complexitySignals.contains(where: { normalized.contains($0) }) {
            return true
        }

        let newlineCount = normalized.filter { $0 == "\n" }.count
        return newlineCount >= 2
    }
}
