import Foundation

/// AITool for mid-task progress reporting. Creates a persistent checkpoint
/// that survives context compression without signing off the task.
struct TaskReportTool: AITool {
    let name = "task_report"
    let description = "Report mid-task progress, findings, or blockers without signing off."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "notes": [
                    "type": "string",
                    "description": "Progress update, findings, blockers, or anything worth persisting."
                ],
                "status": [
                    "type": "string",
                    "enum": ["in_progress", "blocked"],
                    "description": "in_progress (default) or blocked."
                ],
                "blocker_reason": [
                    "type": "string",
                    "description": "Required when status=blocked. Explain what's needed to unblock."
                ]
            ],
            "required": ["notes"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        let notes = raw["notes"] as? String ?? ""
        let status = raw["status"] as? String ?? "in_progress"
        let blockerReason = raw["blocker_reason"] as? String

        guard !notes.isEmpty else {
            return """
            status: error
            message: "notes is required."
            error:
              code: MISSING_NOTES
              recoverable: true
            """
        }

        guard status == "in_progress" || status == "blocked" else {
            return """
            status: error
            message: "status must be 'in_progress' or 'blocked'."
            error:
              code: INVALID_STATUS
              recoverable: true
            """
        }

        if status == "blocked" && (blockerReason?.isEmpty ?? true) {
            return """
            status: error
            message: "blocker_reason is required when status=blocked."
            error:
              code: MISSING_BLOCKER_REASON
              recoverable: true
            """
        }

        // Report is acknowledged — in production this would persist to the plan store
        return """
        status: success
        message: "Checkpoint saved. Task remains active."
        content:
          notes: "\(notes.sanitizedForToolFeedback())"
          status: "\(status)"
        """
    }
}

private extension String {
    func sanitizedForToolFeedback() -> String {
        self.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(2000).description
    }
}
