import Foundation

/// Tool that allows the agent to explicitly generate tactical sub-steps for an implementation plan.
/// This encapsulates the logic previously hardwired into TacticalPlanningNode.
struct TacticalPlanTool: AITool {
    let name = "generate_tactical_plan"
    let description =
        "Generate detailed tactical sub-steps for an existing implementation plan. "
        + "Use this when you have a high-level strategy but need to break it down into concrete file-level actions."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "strategicPlan": [
                    "type": "string",
                    "description": "The current high-level markdown plan.",
                ],
                "userInput": [
                    "type": "string",
                    "description": "The original user objective.",
                ],
            ],
            "required": ["strategicPlan", "userInput"],
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let args = arguments.raw
        guard let strategicPlan = args["strategicPlan"] as? String else {
            throw AppError.aiServiceError("Missing 'strategicPlan' for generate_tactical_plan")
        }
        guard let userInput = args["userInput"] as? String else {
            throw AppError.aiServiceError("Missing 'userInput' for generate_tactical_plan")
        }

        let plan = await TacticalPlanSynthesizer.mergeIntoStrategicPlan(
            strategicPlan: strategicPlan,
            userInput: userInput,
            preserveCurrentPlan: false
        )

        return plan
    }
}

/// Extracted from TacticalPlanningNode to be shared
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
