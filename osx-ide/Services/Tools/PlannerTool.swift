import Foundation

struct PlannerTool: AITool {
    let name = "planner"
    let description = "Create/get/update a persistent high-level execution plan for the current conversation. Intended to be called by the Agent to avoid losing execution context."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "description": "One of: get, set, update, clear.",
                    "enum": ["get", "set", "update", "clear"]
                ],
                "plan": [
                    "type": "string",
                    "description": "Plan content in markdown. Required for set/update."
                ]
            ],
            "required": ["action"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let action = arguments["action"] as? String else {
            throw AppError.aiServiceError("Missing 'action' argument for planner")
        }

        // Injected by AIToolExecutor (not part of the model schema).
        guard let conversationId = arguments["_conversation_id"] as? String, !conversationId.isEmpty else {
            throw AppError.aiServiceError("Missing injected '_conversation_id' for planner")
        }

        switch action {
        case "get":
            let current = await ConversationPlanStore.shared.get(conversationId: conversationId)
            if let current, !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return current
            }
            return "No plan set.\n\nSet one with:\n{\n  \"action\": \"set\",\n  \"plan\": \"- Step 1: ...\\n- Step 2: ...\\n- Step 3: ...\"\n}"

        case "set":
            guard let plan = arguments["plan"] as? String, !plan.isEmpty else {
                throw AppError.aiServiceError("Missing 'plan' for planner.set")
            }
            await ConversationPlanStore.shared.set(conversationId: conversationId, plan: plan)
            await ConversationLogStore.shared.append(conversationId: conversationId, type: "planner.set", data: ["length": plan.count])
            return plan

        case "update":
            guard let plan = arguments["plan"] as? String, !plan.isEmpty else {
                throw AppError.aiServiceError("Missing 'plan' for planner.update")
            }
            let existing = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
            let merged: String
            if existing.isEmpty {
                merged = plan
            } else {
                merged = existing + "\n\n" + plan
            }
            await ConversationPlanStore.shared.set(conversationId: conversationId, plan: merged)
            await ConversationLogStore.shared.append(conversationId: conversationId, type: "planner.update", data: ["appendLength": plan.count, "totalLength": merged.count])
            return merged

        case "clear":
            await ConversationPlanStore.shared.set(conversationId: conversationId, plan: "")
            await ConversationLogStore.shared.append(conversationId: conversationId, type: "planner.clear")
            return "Plan cleared."

        default:
            throw AppError.aiServiceError("Invalid 'action' for planner. Must be one of: get, set, update, clear")
        }
    }
}
