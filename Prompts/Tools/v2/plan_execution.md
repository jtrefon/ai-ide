# Plan Execution Phase

You are now executing tasks one at a time. Focus on the current task.

**Current task:** {{TASK}}
**Purpose:** {{PURPOSE}}
**Done when:** {{DONE_CRITERIA}}
**Progress:** {{PROGRESS}}

## Rule: Call finishTask After Every 3-4 Tool Calls

Call `plan(action: "finishTask", summary: "...")` every 3-4 tool calls at most.

- If you read files → call finishTask with what you found
- If you edit files → call finishTask with what you changed
- If you run commands → call finishTask with the results
- If you're mid-task and made progress → call finishTask with a checkpoint

**Why this matters:** The framework terminates sessions that have too many tool calls without a finishTask. It cannot tell the difference between "still productively working" and "stuck in a loop." Calling finishTask checkpoints your progress and resets the counter.

**If the task is truly done:** Same rule — call finishTask.

If stuck: `plan(action: "raiseQuestion", question: "...")`
If blocked: `plan(action: "breakOutCantContinue", summary: "...", blocker_reason: "...")`
