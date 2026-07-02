import Foundation

/// AITool that completes the current task, stores a permanent summary,
/// advances the plan to the next task, and injects context for it.
struct TaskSignoffTool: AITool {
    let name = "task_signoff"
    let description = "Complete the current task with a summary and advance to the next task."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "summary": [
                    "type": "string",
                    "description": "What was done, files changed, verification result."
                ],
                "blocked": [
                    "type": "boolean",
                    "description": "Set true if task cannot be completed."
                ],
                "blocked_reason": [
                    "type": "string",
                    "description": "Why the task is blocked (required if blocked=true)."
                ]
            ],
            "required": ["summary"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        let conversationId = raw["__conversation_id"] as? String ?? ""
        let summary = raw["summary"] as? String ?? ""
        let blocked = raw["blocked"] as? Bool ?? false
        let reason = raw["blocked_reason"] as? String

        guard !conversationId.isEmpty else {
            return """
            status: error
            message: "No conversation context."
            error:
              code: MISSING_CONTEXT
              recoverable: false
            """
        }

        guard !summary.isEmpty else {
            return """
            status: error
            message: "Summary is required."
            error:
              code: MISSING_SUMMARY
              recoverable: true
            """
        }

        if blocked && (reason?.isEmpty ?? true) {
            return """
            status: error
            message: "blocker_reason is required when blocked=true."
            error:
              code: MISSING_BLOCKER_REASON
              recoverable: true
            """
        }

        let store = ConversationPlanStore.shared
        guard var plan = await store.getPlan(conversationId: conversationId) else {
            return """
            status: error
            message: "No active plan found for this conversation."
            error:
              code: NO_PLAN
              recoverable: false
            """
        }

        guard let activeIndex = plan.items.firstIndex(where: { $0.status == .active }) else {
            return """
            status: error
            message: "No active task found to sign off."
            error:
              code: NO_ACTIVE_TASK
              recoverable: false
            """
        }

        // Record completion
        if blocked {
            plan.items[activeIndex].status = .blocked
            plan.items[activeIndex].summary = summary
            plan.items[activeIndex].blockedReason = reason ?? "No reason provided"
        } else {
            plan.items[activeIndex].status = .completed
            plan.items[activeIndex].summary = summary
        }

        // Advance to next pending
        let nextActive = plan.items.firstIndex(where: { $0.status == .pending })
        if let nextActive {
            plan.currentIndex = nextActive
            plan.items[nextActive].status = .active
        } else {
            plan.currentIndex = plan.items.count
            plan.completedAt = Date()
        }

        await store.setPlan(conversationId: conversationId, plan: plan)

        let completedCount = plan.items.filter { $0.status == .completed || $0.status == .blocked }.count
        let totalCount = plan.items.count

        if let nextActive, nextActive < plan.items.count {
            let next = plan.items[nextActive]
            return """
            status: success
            message: "Task completed. Advancing to task \(completedCount + 1) of \(totalCount)."
            content:
              task_completed: "\(plan.items[activeIndex].id)"
              next_task: "\(next.description)"
              progress: "\(completedCount)/\(totalCount) — \(Int(Double(completedCount) / Double(totalCount) * 100))%"
              details:
                purpose: "\(next.purpose)"
                context: \(next.context)
                done_criteria: "\(next.doneCriteria)"
            """
        } else {
            return """
            status: success
            message: "All \(totalCount) tasks complete. Ready for final summary."
            content:
              task_completed: "\(plan.items[activeIndex].id)"
              progress: "\(completedCount)/\(totalCount) — 100%"
              all_done: true
            """
        }
    }
}
