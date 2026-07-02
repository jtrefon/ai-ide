# plan Tool

## Purpose
Track progress through a structured plan for multi-step tasks. Helps you architect your approach, follow it with precision, and maintain focus across multiple turns.

## When to Use
- Any task or project that might need more than one turn to complete
- When the work involves multiple files, steps, or phases
- When you want to break down a complex request into manageable steps
- When you need to maintain focus and avoid losing track of what's been done

## When NOT to Use
- Do NOT use for single-turn tasks that can be completed immediately
- Do NOT use when you're just answering a question or having a conversation

## Parameters
- **action** (required, string): `"report"` | `"complete"` | `"blocked"`
  - `report`: Checkpoint progress mid-task. Task continues.
  - `complete`: Finish the current task and advance to the next.
  - `blocked`: Task cannot proceed. Provide blocker_reason.
- **summary** (required, string): What happened — progress update, what was done, or why blocked. Be specific about files, decisions, and results.
- **blocker_reason** (optional, string): Required when action=blocked. What is needed to unblock.

## Usage Examples
- Simple report: `{ "action": "report", "summary": "Read all 3 persistence files. Found CoreData used directly in view models." }`
- Complete task: `{ "action": "complete", "summary": "Created TodoRepository protocol. Build passes. Ready for implementation." }`
- Blocked: `{ "action": "blocked", "summary": "Cannot implement — missing CoreData entity.", "blocker_reason": "TodoEntity.xcdatamodeld doesn't exist yet." }`

## Output Structure
Returns a ToolFeedback envelope:
- **action=report**: `status: success`, message confirms progress recorded, task continues.
- **action=complete**: `status: success`, includes next_task description, purpose, and done_criteria. If all done, includes all_done: true.
- **action=blocked**: `status: blocked`, includes progress and blocker recorded confirmation.

## Success Indicators
- report: status "success" — checkpoint saved, keep working
- complete: next_task is provided — you have fresh context for the next step
- complete with all_done: true — ready for final summary
- blocked: status "blocked" — blocker recorded, framework can help

## Error Handling
- INVALID_ACTION: action must be "report", "complete", or "blocked"
- MISSING_SUMMARY: summary is required for all actions
- MISSING_BLOCKER_REASON: blocker_reason is required when action=blocked
- NO_ACTIVE_TASK: no active task found (call complete when one is active)

## Best Practices
1. Use `report` to checkpoint significant progress — not for every small step
2. Use `complete` only when you've verified the work (read files back, ran tests)
3. Use `blocked` when you genuinely cannot proceed — explain exactly what's needed
4. A blocked task allows the plan to continue — the user can address the blocker
5. Keep summaries specific about files, functions, and decisions made
