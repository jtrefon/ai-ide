import Foundation

@MainActor
enum BranchExecutionPlanner {
    static func makeBranchExecution(
        tacticalPlan: String,
        userInput: String
    ) -> OrchestrationState.BranchExecution? {
        let branches = extractBranches(from: tacticalPlan)
        guard !branches.isEmpty else { return nil }

        let invariants = makeGlobalInvariants(userInput: userInput, tacticalPlan: tacticalPlan)
        return OrchestrationState.BranchExecution(
            plan: tacticalPlan,
            globalInvariants: invariants,
            branches: branches,
            activeBranchIndex: 0
        )
    }

    private static func makeGlobalInvariants(userInput: String, tacticalPlan: String) -> [String] {
        var invariants: [String] = []
        let normalizedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedInput.isEmpty {
            invariants.append("Primary objective: \(normalizedInput)")
        }

        let normalizedPlan = tacticalPlan.lowercased()
        if normalizedPlan.contains("do not run") {
            invariants.append("Honor task constraints from the plan and avoid prohibited commands.")
        }
        if normalizedPlan.contains("minimal") {
            invariants.append("Prefer minimal, focused edits over broad rewrites.")
        }
        if normalizedPlan.contains("verify") || normalizedPlan.contains("validate") {
            invariants.append("Preserve a verifiable path to completion before final delivery.")
        }
        return invariants
    }

    private static func extractBranches(from tacticalPlan: String) -> [OrchestrationState.BranchExecution.Branch] {
        let lines = tacticalPlan.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var branches: [OrchestrationState.BranchExecution.Branch] = []
        var currentTitle: String?
        var currentChecklistItems: [String] = []
        var currentIndex = 0

        func flushCurrentBranch() {
            guard let currentTitle else { return }
            currentIndex += 1
            branches.append(
                OrchestrationState.BranchExecution.Branch(
                    id: "branch_\(currentIndex)",
                    title: sanitizeTitle(currentTitle),
                    checklistItems: currentChecklistItems
                )
            )
        }

        for rawLine in lines {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            if let title = numberedStepTitle(from: trimmedLine) {
                flushCurrentBranch()
                currentTitle = title
                currentChecklistItems = []
                continue
            }

            guard currentTitle != nil else { continue }
            if let checklistItem = checklistTitle(from: trimmedLine) {
                currentChecklistItems.append(checklistItem)
            }
        }

        flushCurrentBranch()
        return branches.filter { !$0.title.isEmpty }
    }

    private static func numberedStepTitle(from line: String) -> String? {
        guard let first = line.first, first.isNumber,
              let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }
        let title = String(line[line.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func checklistTitle(from line: String) -> String? {
        guard line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") || line.hasPrefix("- [X]") else {
            return nil
        }
        let title = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func sanitizeTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "[ ]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
