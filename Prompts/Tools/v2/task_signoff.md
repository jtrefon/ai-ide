# task_signoff Tool

## Purpose
Complete the current task, provide a permanent summary of what was done, and advance to the next task. The summary is stored permanently and survives context compression.

**Why use this tool:** When you call task_signoff, the framework injects the next task's full context — purpose, relevant files, and done criteria — directly into your view. You get a fresh, focused task with everything you need to know, every time. Without it, you'd have to remember what comes next and manually track progress across turns. Your summaries are also used for the final review when all tasks are done.

## When to Use
- When you have COMPLETED the current task — all done criteria are met
- When you have VERIFIED the work — read files back, run builds/tests, confirmed correctness
- When the task is BLOCKED and cannot proceed — call with blocked=true

## When NOT to Use
- Do NOT use for partial progress — use `task_report` instead
- Do NOT use to skip tasks — the framework advances sequentially
- Do NOT use without verifying — read back files, run commands, confirm it works

## Parameters
- **summary** (required, string): What was done, what files were created/modified, verification result. Write this as if you'll need to recover context after compression — be specific.
- **blocked** (optional, boolean): Set true if this task cannot be completed.
- **blocked_reason** (optional, string): Required if blocked=true. Explain why and what's needed.

## Usage Examples
- Complete task: `{ "summary": "Created TodoRepository protocol with CRUD methods (create, read, update, delete). Build passes. Ready for implementation." }`
- Blocked: `{ "summary": "Cannot implement TodoRepository — missing CoreData entity definition.", "blocked": true, "blocked_reason": "TodoEntity.xcdatamodeld doesn't exist yet. Need to create the CoreData model first." }`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success" | "blocked"
- **message**: "Task completed. Advancing to task 2 of 5." or "Task blocked. Reason recorded."
- **content**:
  - `task_completed`: ID of the completed task
  - `next_task`: Description of the next task (if any)
  - `progress`: "2/5 — 40% complete"
  - `message`: Human-readable handoff message

## Success Indicators
- status: "success" — task was completed and summary recorded
- next_task is shown — you can now work on it
- progress < 100% — there are more tasks remaining
- After the last task, the framework will ask for a final summary

## Error Handling
- INVALID_STATE: No active task to sign off (call task_report instead)
- MISSING_SUMMARY: summary is required
- MISSING_BLOCKER_REASON: blocker_reason is required when blocked=true

## Best Practices
1. Always VERIFY before signing off — read files back, run the build, check for errors
2. Write summaries that would reorient you after context compression — include file paths, function names, key decisions
3. Keep summaries focused on WHAT was done, not HOW — the details are in the code
4. If blocked, explain EXACTLY what is blocking and what's needed to unblock
5. A summary of "Done." is not useful — be specific

## Integration Notes
- Summaries are stored permanently and survive compression
- After ALL tasks are complete, all summaries are shown together for a final review
- The framework tracks completion — you cannot skip tasks
- Blocked tasks ALLOW the framework to exit the loop, but the blocker is logged
