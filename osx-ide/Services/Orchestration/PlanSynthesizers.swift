import Foundation

/// Plan synthesis logic extracted from StrategicPlanTool and TacticalPlanTool.
/// Used by StrategicPlanningNode and TacticalPlanningNode in the orchestration graph.

@MainActor
enum StrategicPlanSynthesizer {
    static func build(userInput: String) -> String {
        return """
            # Implementation Plan

            **Goal:** \(userInput)

            ## Strategy
            1. [ ] Identify target files and understand current structure
            2. [ ] Design minimal change set to satisfy the request
            3. [ ] Implement changes
            4. [ ] Verify correctness and report completion
            """
    }

    /// Generate a structured TaskPlan from the user input.
    static func buildStructured(userInput: String, mode: AIMode) -> TaskPlan {
        let normalized = userInput.lowercased()
        let domain: PlanDomain = {
            if normalized.contains("architecture") || normalized.contains("design") { return .architecture }
            if normalized.contains("research") || normalized.contains("investigate") || normalized.contains("evaluate") { return .research }
            if normalized.contains("refactor") || normalized.contains("migrate") || normalized.contains("restructure") { return .refactor }
            if normalized.contains("analyze") || normalized.contains("audit") || normalized.contains("review") { return .analysis }
            return .implementation
        }()

        return TaskPlan(
            id: UUID().uuidString,
            goal: userInput,
            value: "Complete the requested task with verified, working results",
            domain: domain,
            mode: mode,
            items: [
                PlanItem(id: "task-1",
                    description: "Explore and understand the relevant codebase areas",
                    purpose: "Must understand current state before making changes",
                    context: ["Use list_files, find_file, search_project to locate relevant files"],
                    doneCriteria: "All relevant files identified and read",
                    status: .pending, summary: nil, blockedReason: nil),
                PlanItem(id: "task-2",
                    description: "Plan the approach and identify files to modify",
                    purpose: "Clear roadmap minimizes wasted work and ensures consistency",
                    context: ["Review findings from task 1"],
                    doneCriteria: "Exact list of files to create/modify is known",
                    status: .pending, summary: nil, blockedReason: nil),
                PlanItem(id: "task-3",
                    description: "Implement the changes",
                    purpose: "Execute the planned modifications",
                    context: ["Read files before editing", "Use patch_file for edits", "Use write_file for new files"],
                    doneCriteria: "All planned changes applied successfully",
                    status: .pending, summary: nil, blockedReason: nil),
                PlanItem(id: "task-4",
                    description: "Verify correctness and summarize",
                    purpose: "Ensure the changes work and nothing is broken",
                    context: ["Run build/tests if applicable", "Read back modified files to verify"],
                    doneCriteria: "Changes verified and final summary ready",
                    status: .pending, summary: nil, blockedReason: nil)
            ],
            createdAt: Date(),
            completedAt: nil,
            currentIndex: 0
        )
    }
}

@MainActor
enum TacticalPlanSynthesizer {
    static func mergeIntoStrategicPlan(
        strategicPlan: String, userInput: String, preserveCurrentPlan: Bool
    ) -> String {
        let strategicSteps = extractNumberedSteps(from: strategicPlan)

        if strategicSteps.isEmpty {
            return """
                # Implementation Plan

                **Goal:** \(userInput)

                ## Strategy
                1. [ ] Analyze requirements and identify target files
                   - [ ] Read relevant source files to understand structure
                   - [ ] Identify dependencies and constraints
                2. [ ] Implement changes with minimal footprint
                   - [ ] Apply focused edits to each target file
                   - [ ] Ensure consistency across changes
                3. [ ] Verify and deliver
                   - [ ] Confirm all changes are correct
                   - [ ] Report completion status
                """
        }

        var lines: [String] = []
        let planLines = strategicPlan.split(separator: "\n", omittingEmptySubsequences: false).map(
            String.init)

        for line in planLines {
            lines.append(line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let step = strategicSteps.first(where: { trimmed == $0.raw }) {
                for substep in step.tacticalSteps {
                    lines.append("   - [ ] \(substep)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private struct StrategicStep {
        let raw: String
        let title: String
        let tacticalSteps: [String]
    }

    private static func extractNumberedSteps(from plan: String) -> [StrategicStep] {
        let lines = plan.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.compactMap { line in
            guard let first = line.first, first.isNumber,
                let dotIndex = line.firstIndex(of: ".")
            else { return nil }
            let title = String(line[line.index(after: dotIndex)...]).trimmingCharacters(
                in: .whitespaces)
            let substeps = generateTacticalSubsteps(for: title)
            return StrategicStep(raw: line, title: title, tacticalSteps: substeps)
        }
    }

    private static func generateTacticalSubsteps(for strategicTitle: String) -> [String] {
        let lower = strategicTitle.lowercased()
        if lower.contains("identify") || lower.contains("understand") || lower.contains("analyze") {
            return [
                "Use read_file/list_files to inspect relevant sources",
                "Note file paths, exports, and dependencies",
            ]
        } else if lower.contains("design") || lower.contains("minimal")
            || lower.contains("change set")
        {
            return [
                "Determine exact edits needed per file",
                "Ensure no unnecessary side effects",
            ]
        } else if lower.contains("implement") || lower.contains("execute")
            || lower.contains("change")
        {
            return [
                "Apply edits using write_file/replace_in_file",
                "Create new files if needed with write_files",
            ]
        } else if lower.contains("verify") || lower.contains("validate") || lower.contains("report")
        {
            return [
                "Confirm file contents match expectations",
                "Summarize what was done and any remaining items",
            ]
        }
        return ["Execute this step with appropriate tools"]
    }
}
