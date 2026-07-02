# plan Tool

## Purpose
Break down complex work into structured, focused tasks. Once you call this tool, you commit to completing all tasks — you'll work through them one at a time, receiving full context for each. There's no way out except finishing or explicitly breaking out.

## When to Use
- Any task that needs multiple steps, files, or phases
- When you want to architect an approach and follow it with precision
- When you need to maintain focus and not lose track of what's been done
- **First call**: Use `plan(action: "finishTask", summary: "your request")` to opt in

## When NOT to Use
- Do NOT use for single-turn tasks you can complete immediately
- Do NOT use when just answering a question or having a conversation

## Parameters
- **action** (required, string): `"finishTask"` | `"raiseQuestion"` | `"breakOutCantContinue"`
  - `finishTask`: Complete the current task and advance to the next. The framework returns the next task's full context (description, purpose, files, done criteria).
  - `raiseQuestion`: Ask the user for clarification mid-plan. The framework pauses and waits for their response.
  - `breakOutCantContinue`: Abort the plan. All remaining tasks are marked blocked. Provide a clear reason.
- **summary** (optional, string): Required for finishTask and breakOutCantContinue. What was done, or why you can't continue.
- **question** (optional, string): Required for raiseQuestion. The question for the user.
- **blocker_reason** (optional, string): Required for breakOutCantContinue. What is needed to unblock.

## Usage Examples
- Opt in: `{ "action": "finishTask", "summary": "Refactor persistence into repository pattern" }`
- Complete task: `{ "action": "finishTask", "summary": "Created TodoRepository protocol. Build passes." }`
- Ask question: `{ "action": "raiseQuestion", "question": "Should the repository use async/await or Combine?" }`
- Break out: `{ "action": "breakOutCantContinue", "summary": "Cannot implement — missing CoreData model.", "blocker_reason": "TodoEntity.xcdatamodeld doesn't exist. Need to create the CoreData schema first." }`

## Output Structure
Returns a ToolFeedback envelope:
- **finishTask (not last)**: `status: success`, includes `task`, `purpose`, `context`, `done_criteria` for the next task. A message like "Well done. Now working on task 2 of 5."
- **finishTask (last)**: `status: success`, includes `all_done: true`. Message asks for final summary.
- **raiseQuestion**: `status: question`, includes the question. Framework pauses for user input.
- **breakOutCantContinue**: `status: blocked`, includes reason and progress. Plan is terminated.

## Success Indicators
- finishTask: next task context is provided — you have everything you need to work on it
- finishTask with all_done: all tasks complete — provide a final summary
- raiseQuestion: status "question" — user will respond
- breakOutCantContinue: status "blocked" — plan aborted

## Error Handling
- INVALID_ACTION: action must be "finishTask", "raiseQuestion", or "breakOutCantContinue"
- MISSING_SUMMARY: summary is required for finishTask and breakOutCantContinue
- MISSING_QUESTION: question is required for raiseQuestion
- MISSING_BLOCKER_REASON: blocker_reason is required for breakOutCantContinue

## Best Practices
1. **First call**: Call `plan(action: "finishTask", summary: "your goal")` to opt in. The framework creates a structured plan.
2. **Complete work before calling finishTask**: Verify by reading files back, running builds, checking tests.
3. **Use raiseQuestion when truly stuck**: Don't guess — ask. The user will respond with clarification.
4. **Use breakOutCantContinue only as a last resort**: Explain exactly what's needed to unblock.
5. **Keep summaries specific**: Include file paths, functions, and key decisions made.
