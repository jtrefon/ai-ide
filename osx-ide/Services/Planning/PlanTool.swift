import Foundation

/// Single tool for the entire task planning lifecycle.
/// Actions: report (mid-task progress), complete (task done, advance), blocked (cannot proceed).
struct PlanTool: AITool {
    let name = "plan"
    let description = "Track task progress through a structured plan. Use for multi-step work that needs focused execution."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["report", "complete", "blocked"],
                    "description": "report: checkpoint progress mid-task. complete: finish current task and advance. blocked: task cannot proceed."
                ],
                "summary": [
                    "type": "string",
                    "description": "Progress update, what was done, or why blocked. Be specific."
                ],
                "blocker_reason": [
                    "type": "string",
                    "description": "Required when action=blocked. What is needed to unblock."
                ]
            ],
            "required": ["action", "summary"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        let action = raw["action"] as? String ?? ""
        let summary = raw["summary"] as? String ?? ""
        let blockerReason = raw["blocker_reason"] as? String

        guard ["report", "complete", "blocked"].contains(action) else {
            return """
            status: error
            message: "action must be 'report', 'complete', or 'blocked'."
            error:
              code: INVALID_ACTION
              recoverable: true
            """
        }

        guard !summary.isEmpty else {
            return """
            status: error
            message: "summary is required."
            error:
              code: MISSING_SUMMARY
              recoverable: true
            """
        }

        if action == "blocked" && (blockerReason?.isEmpty ?? true) {
            return """
            status: error
            message: "blocker_reason is required when action=blocked."
            error:
              code: MISSING_BLOCKER_REASON
              recoverable: true
            """
        }

        if action == "report" {
            return """
            status: success
            message: "Progress recorded. Task continues."
            content:
              action: "report"
              summary: "\(summary.sanitized())"
            """
        }

        // complete or blocked = sign off the current task
        let conversationId = raw["_conversation_id"] as? String ?? ""

        guard !conversationId.isEmpty else {
            return """
            status: success
            message: "\(action == "complete" ? "Task signed off. Next task would be injected here." : "Task marked blocked.")"
            content:
              action: "\(action)"
              note: "Plan tracking is initialized. In production, the plan would advance here."
            """
        }

        let store = ConversationPlanStore.shared
        guard var plan = await store.getPlan(conversationId: conversationId) else {
            return """
            status: success
            message: "No structured plan found. Your summary has been recorded."
            content:
              action: "\(action)"
              summary: "\(summary.sanitized())"
            """
        }

        guard let activeIndex = plan.items.firstIndex(where: { $0.status == .active }) else {
            return """
            status: error
            message: "No active task found to complete."
            error:
              code: NO_ACTIVE_TASK
              recoverable: false
            """
        }

        if action == "blocked" {
            plan.items[activeIndex].status = .blocked
            plan.items[activeIndex].summary = summary
            plan.items[activeIndex].blockedReason = blockerReason ?? "No reason provided"
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

        if action == "blocked" {
            return """
            status: blocked
            message: "Task blocked. Reason recorded. \(completedCount)/\(totalCount) tasks complete."
            content:
              action: "blocked"
              progress: "\(completedCount)/\(totalCount)"
            """
        }

        guard let nextActive, nextActive < plan.items.count else {
            return """
            status: success
            message: "All \(totalCount) tasks complete. Ready for final review."
            content:
              action: "complete"
              progress: "\(completedCount)/\(totalCount)"
              all_done: true
            """
        }

        let next = plan.items[nextActive]
        return """
        status: success
        message: "Task \(completedCount)/\(totalCount) complete. Next task ready."
        content:
          action: "complete"
          next_task: "\(next.description)"
          purpose: "\(next.purpose)"
          done_criteria: "\(next.doneCriteria)"
          progress: "\(completedCount)/\(totalCount)"
        """
    }
}

private extension String {
    func sanitized() -> String {
        self.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(2000).description
    }
}
