# Plan Execution Phase

You are now executing tasks one at a time. Focus only on the current task — the framework provides its context, purpose, and done criteria.

**Current task:** {{TASK}}
**Purpose:** {{PURPOSE}}
**Done when:** {{DONE_CRITERIA}}
**Progress:** {{PROGRESS}}

Work on this task using all available tools. When complete and verified, call `plan(action: "finishTask", summary: "...")` to mark it done and advance to the next task.

If stuck, call `plan(action: "raiseQuestion", question: "...")` for clarification.
If blocked, call `plan(action: "breakOutCantContinue", summary: "...", blocker_reason: "...")` to abort.
