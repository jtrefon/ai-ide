import Foundation

/// Tool that allows the agent to explicitly generate a high-level implementation plan.
/// This encapsulates the logic previously hardwired into StrategicPlanningNode.
struct StrategicPlanTool: AITool {
    let name = "generate_implementation_plan"
    let description =
        "Generate a structured high-level implementation plan for a complex task. "
        + "Use this for multi-file refactors or significant changes to understand the scope before executing edits."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "userInput": [
                    "type": "string",
                    "description": "A concise summary of the task to be planned.",
                ]
            ],
            "required": ["userInput"],
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let args = arguments.raw
        guard let userInput = args["userInput"] as? String else {
            throw AppError.aiServiceError("Missing 'userInput' for generate_implementation_plan")
        }

        // We use the same synthesizer logic as the old hardwired node
        let plan = await StrategicPlanSynthesizer.build(userInput: userInput)

        // Note: The caller (Dispatcher/ToolLoop) will handle appending this to history
        // to ensure it's visible in the UI and context.
        return plan
    }
}

/// Extracted from StrategicPlanningNode to be shared
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
}
