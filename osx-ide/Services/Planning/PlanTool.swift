import Foundation

/// The planning tool — once the model opts in, it is confined to the planning sub-loop
/// until all tasks are complete or it explicitly breaks out.
///
/// Actions:
/// - finishTask: complete current task, receive next task context
/// - raiseQuestion: ask the user for clarification mid-plan
/// - breakOutCantContinue: abort the plan with a reason
struct PlanTool: AITool {
    let name = "plan"
    let description = "Structured task planner. First call enters planning mode — research the problem using all tools, explore the codebase, understand scope. Second call locks your plan and starts execution. Then call finishTask after each task to advance."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["finishTask", "raiseQuestion", "breakOutCantContinue"],
                    "description": "finishTask: complete current task and advance. raiseQuestion: ask user for clarification. breakOutCantContinue: abort the plan."
                ],
                "summary": [
                    "type": "string",
                    "description": "Required for finishTask and breakOutCantContinue. What was done, or why you can't continue."
                ],
                "question": [
                    "type": "string",
                    "description": "Required for raiseQuestion. The question to ask the user."
                ],
                "blocker_reason": [
                    "type": "string",
                    "description": "Required for breakOutCantContinue. What is needed to unblock."
                ]
            ],
            "required": ["action"]
        ]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        let action = raw["action"] as? String ?? ""
        let summary = raw["summary"] as? String ?? ""
        let question = raw["question"] as? String ?? ""
        let blockerReason = raw["blocker_reason"] as? String
        let conversationId = raw["_conversation_id"] as? String ?? ""

        guard ["finishTask", "raiseQuestion", "breakOutCantContinue"].contains(action) else {
            return """
            status: error
            message: "action must be 'finishTask', 'raiseQuestion', or 'breakOutCantContinue'."
            error:
              code: INVALID_ACTION
              recoverable: true
            """
        }

        // raiseQuestion — no plan needed, just relay the question
        if action == "raiseQuestion" {
            guard !question.isEmpty else {
                return """
                status: error
                message: "question is required."
                error:
                  code: MISSING_QUESTION
                  recoverable: true
                """
            }
            return """
            status: question
            message: "\(question.sanitized())"
            content:
              action: "raiseQuestion"
              question: "\(question.sanitized())"
            """
        }

        // finishTask and breakOutCantContinue need a summary
        guard !summary.isEmpty else {
            return """
            status: error
            message: "summary is required for finishTask and breakOutCantContinue."
            error:
              code: MISSING_SUMMARY
              recoverable: true
            """
        }

        if action == "breakOutCantContinue" && (blockerReason?.isEmpty ?? true) {
            return """
            status: error
            message: "blocker_reason is required for breakOutCantContinue."
            error:
              code: MISSING_BLOCKER_REASON
              recoverable: true
            """
        }

        // If no conversation context, we can't persist — provide a session-local plan
        guard !conversationId.isEmpty else {
            return """
            status: success
            message: "Plan tool initialised. Work on the current task and call finishTask when done."
            content:
              action: "\(action)"
              note: "You've opted into structured planning. Complete each task and call finishTask to advance."
            """
        }

        let store = ConversationPlanStore.shared

        // Fetch or initialise the plan
        if var plan = await store.getPlan(conversationId: conversationId) {
            // Check if we're transitioning from planning to execution
            if plan.items.isEmpty && action == "finishTask" {
                // Second call: agent has finished researching and is proposing the plan
                let taskItem = PlanItem(id: "task-1",
                    description: summary,
                    purpose: "As planned during research phase",
                    context: [],
                    doneCriteria: "Work is complete and verified",
                    status: .active,
                    summary: nil,
                    blockedReason: nil)
                plan.items = [taskItem]
                plan.currentIndex = 0
                await store.setPlan(conversationId: conversationId, plan: plan)
                return """
                status: success
                message: "Plan locked. You've opted into structured execution. Work on the task and call finishTask when done to advance."
                content:
                  action: "finishTask"
                  task: "\(summary)"
                  progress: "0/1"
                """
            }

            // Existing plan with items — advance or break
            guard let activeIndex = plan.items.firstIndex(where: { $0.status == .active }) else {
                return """
                status: error
                message: "No active task found."
                error:
                  code: NO_ACTIVE_TASK
                  recoverable: false
                """
            }

            if action == "breakOutCantContinue" {
                plan.items[activeIndex].status = .blocked
                plan.items[activeIndex].summary = summary
                plan.items[activeIndex].blockedReason = blockerReason ?? "No reason provided"
                // Abandon remaining
                for i in (activeIndex + 1)..<plan.items.count {
                    plan.items[i].status = .blocked
                    plan.items[i].blockedReason = "Abandoned — prior task blocked"
                }
                plan.completedAt = Date()
                await store.setPlan(conversationId: conversationId, plan: plan)
                let total = plan.items.count
                return """
                status: blocked
                message: "Plan aborted. \(activeIndex + 1)/\(total) tasks completed before block."
                content:
                  action: "breakOutCantContinue"
                  reason: "\(blockerReason?.sanitized() ?? "")"
                  progress: "\(activeIndex + 1)/\(total)"
                """
            }

            // finishTask — mark complete, advance
            plan.items[activeIndex].status = .completed
            plan.items[activeIndex].summary = summary

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

            guard let nextActive, nextActive < plan.items.count else {
                return """
                status: success
                message: "All \(totalCount) tasks complete. Provide a final summary of what was achieved."
                content:
                  action: "finishTask"
                  all_done: true
                  progress: "\(completedCount)/\(totalCount)"
                """
            }

            let next = plan.items[nextActive]
            return """
            status: success
            message: "Well done. Task \(completedCount)/\(totalCount) complete. Now working on task \(completedCount + 1)."
            content:
              action: "finishTask"
              task: "\(next.description)"
              purpose: "\(next.purpose)"
              context: \(next.context.map { "\"\($0)\"" }.joined(separator: ", "))
              done_criteria: "\(next.doneCriteria)"
              progress: "\(completedCount)/\(totalCount)"
            """
        } else {
            // No plan exists — enter planning mode.
            // Agent researches using all tools, then calls finishTask to transition to execution.
            let planningPlan = TaskPlan(
                id: UUID().uuidString,
                goal: summary,
                value: "Complete the requested work",
                domain: .implementation,
                mode: .coder,
                items: [],
                createdAt: Date(),
                completedAt: nil,
                currentIndex: 0
            )
            await store.setPlan(conversationId: conversationId, plan: planningPlan)
            return """
            status: success
            message: "Planning mode. Research the problem using all available tools — read files, search the codebase, browse the web, run commands. Understand the current state and explore what's needed. When you have a clear plan, call finishTask again with your proposed task breakdown."
            content:
              action: "finishTask"
              phase: "planning"
            """
        }
    }
}

private extension String {
    func sanitized() -> String {
        self.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(2000).description
    }
}
