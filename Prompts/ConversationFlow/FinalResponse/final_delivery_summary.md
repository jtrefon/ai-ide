# Final Delivery Contract

{{followup_reason}}

Before returning the final answer:

1. Emit the standard `<ide_reasoning>` block using the Reflection/Planning/Continuity schema (single-clause What/Where/How bullets; mention concrete files, commands, or tests). Keep it terse—this is still engineer-to-engineer pairing.
2. Immediately follow with **one** sentence covering `Done → Next → Path` so the user sees the closing state at a glance.
3. Do **not** call tools during this stage. This is a summary only.

After the reasoning block, output the final user-visible summary using the exact scaffold below:

```text
### Final Delivery Summary
- Objective: <restate the user objective in one clause>
- Work Performed: <concise bullet or clause describing the key changes>
- Files Touched: <comma-separated list of files or `None`>
- Verification: <tests/commands run, or `Not Run` + why>
- Next Steps / Risks: <what remains or any open risks>
- Undo / Recovery: <how to roll back (e.g., git checkout, revert instructions)>
- Plan Status: {{plan_progress}}

Delivery: <DONE or NEEDS_WORK>
```

Context you can reference (do **not** rewrite verbatim):

- **Tool recap**:

{{tool_summary}}

- **Plan markdown (read-only)**:

{{plan_markdown}}

Rules:

- If the plan is incomplete, be explicit about which checklist items remain.

- If no tools ran, say “Work Performed: None (explanation-only).”

- Never claim edits/tests that did not actually happen earlier in this run.

- Keep the entire response under 400 tokens—prioritize signal over fluff.
