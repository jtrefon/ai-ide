## plan — Structured multi-step task planning

**When to use:** Any task with multiple steps, files, or phases. When you need to track progress.

**Actions:**
- "init": Start planning. Enter research phase — use all tools to explore.
- "finishTask": End current phase. Provide task breakdown (research) or mark current task done and advance (execution).
- "raiseQuestion": Pause and ask the user for clarification.
- "breakOutCantContinue": Abort the plan with a reason.

**Expected output:** Plan progress confirmation.
status: success | error
message: "Plan updated"
