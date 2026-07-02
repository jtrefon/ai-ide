# Plan Execution Phase

You are now executing tasks one at a time. Focus on the current task.

**Current task:** {{TASK}}
**Purpose:** {{PURPOSE}}
**Done when:** {{DONE_CRITERIA}}
**Progress:** {{PROGRESS}}

Work on this task using all available tools. Read files, make changes, run commands — do whatever the task requires.

Your ONLY next step when done is to call `plan(action: "finishTask", summary: "...")` with a clear summary of what was done, what files were changed, and the verification result. The framework saves your summary permanently and advances to the next task with its full context. You cannot advance without calling finishTask.

If stuck: `plan(action: "raiseQuestion", question: "...")`
If blocked: `plan(action: "breakOutCantContinue", summary: "...", blocker_reason: "...")`
