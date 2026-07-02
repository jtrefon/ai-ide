# task_report Tool

## Purpose
Report mid-task progress, findings, or blockers without signing off. Creates a permanent checkpoint that survives context compression.

**Why use this tool:** Your notes are saved permanently. After the conversation is compacted, your last report is re-injected into context — so you don't lose your place. Without this, all mid-task context is lost on compression and you'd have to rediscover where you were.

## When to Use
- **Mid-task checkpoint**: You've completed a significant sub-step and want to persist progress
- **Found something unexpected**: The codebase is different from assumed — document your findings
- **Getting stuck**: Report a blocker with full context so the framework can help
- **Long task**: A task takes many turns — checkpoint to survive conversation compression
- **Changed approach**: You decided on a different strategy than initially planned

## When NOT to Use
- Do NOT use when the task is complete — use `task_signoff` instead
- Do NOT use for trivial progress ("still working") — only meaningful checkpoints
- Do NOT use to ask questions — just keep working

## Parameters
- **notes** (required, string): Progress update, findings, blockers, or anything worth persisting. Be specific — include file paths, decisions, and reasoning.
- **status** (optional, string): `"in_progress"` (default) or `"blocked"`.
- **blocker_reason** (optional, string): Required when status is `"blocked"`. Explain exactly what is needed to unblock.

## Usage Examples
- Progress checkpoint: `{ "notes": "Read all 3 persistence files. Found CoreData is used directly in view models — no abstraction layer." }`
- Blocked: `{ "notes": "Cannot find the Todo model file.", "status": "blocked", "blocker_reason": "Expected src/models/Todo.swift but the directory doesn't exist. Need to locate the correct path." }`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success"
- **message**: "Checkpoint saved. Task remains active."
- **content**: Empty (no data returned — just confirmation)

## Success Indicators
- status: "success" — the report was persisted
- The task remains active — keep working

## Error Handling
- INVALID_STATUS: status must be "in_progress" or "blocked"
- MISSING_BLOCKER_REASON: blocker_reason is required when status is "blocked"

## Best Practices
1. Be specific in your notes — include file paths, line numbers, and code patterns
2. Use status="blocked" only when you genuinely cannot proceed without help
3. A blocked task may trigger a framework response — the framework may offer alternatives
4. Checkpoints are permanent — they survive context compression and can be referenced later
5. Don't over-report — one checkpoint per significant sub-step is enough

## Integration Notes
- Reports are stored alongside the plan in ConversationPlanStore
- After context compression, the last report is re-injected to help you recover
- A blocked status updates the plan item's status in the framework
