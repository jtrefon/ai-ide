import Foundation

struct ContemplationTool: AITool {
    let name = "contemplate"
    let description =
        "Think more deeply about a task before acting. Use this when the problem is ambiguous, risky, or requires a more deliberate approach. Returns structured JSON with a concise analysis, recommended approach, and whether execution should continue."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "task": [
                    "type": "string",
                    "description": "The current task or subproblem to contemplate."
                ],
                "context": [
                    "type": "string",
                    "description": "Optional supporting context, constraints, or discoveries."
                ]
            ],
            "required": ["task"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let rawArguments = arguments.raw
        guard let task = rawArguments["task"] as? String,
              !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.aiServiceError("Missing 'task' for contemplate")
        }

        let context = (rawArguments["context"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContext = (context?.isEmpty == false) ? context : nil
        let result = ContemplationToolResult(
            task: task,
            analysis: buildAnalysis(task: task, context: normalizedContext),
            recommendedApproach: buildRecommendedApproach(task: task, context: normalizedContext),
            shouldProceed: true,
            requiresPlanUpdate: looksComplex(task, context: normalizedContext)
        )
        let data = try JSONEncoder().encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AppError.aiServiceError("Failed to encode contemplate result")
        }
        return json
    }

    private func buildAnalysis(task: String, context: String?) -> [String] {
        var analysis = [
            "Clarify the target outcome before making edits.",
            "Prefer focused inspection of the smallest relevant file set.",
            "Avoid mutation until the intended change set is concrete."
        ]

        if looksComplex(task, context: context) {
            analysis.append("This looks multi-step or cross-cutting, so explicit planning may help before execution.")
        }

        if let context, !context.isEmpty {
            analysis.append("Relevant context was provided and should guide the next action: \(context)")
        }

        return analysis
    }

    private func buildRecommendedApproach(task: String, context: String?) -> [String] {
        var steps = [
            "Inspect the relevant code or files first.",
            "If the change spans multiple concerns, call a planning tool before editing.",
            "Execute with concrete tools only after the path is clear."
        ]

        if looksComplex(task, context: context) {
            steps.insert("Generate a structured implementation plan.", at: 1)
        }

        return steps
    }

    private func looksComplex(_ task: String, context: String?) -> Bool {
        let normalized = [task, context]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        let signals = [
            "multiple files",
            "step by step",
            "re-architect",
            "refactor",
            "migrate",
            "complex",
            "across"
        ]

        return signals.contains(where: { normalized.contains($0) })
    }
}

private struct ContemplationToolResult: Encodable {
    let task: String
    let analysis: [String]
    let recommendedApproach: [String]
    let shouldProceed: Bool
    let requiresPlanUpdate: Bool
}
