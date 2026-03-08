# Final Response Contract

{{followup_reason}}

Before returning the final answer:

1. Emit the standard `<ide_reasoning>` block using the Reflection/Planning/Continuity schema (single-clause What/Where/How bullets; mention concrete files, commands, or tests). Keep it terse—this is still engineer-to-engineer pairing.
2. Immediately follow with **one** sentence covering `Done → Next → Path` so the user sees the closing state at a glance.
3. Do **not** call tools during this stage. This is a summary only.

After the reasoning block, output a concise user-visible final summary in plain text.
Cover the user objective, the work performed, the verification status, and any remaining next steps or risks.
Mention files only when they materially matter.
Do not use headings, rigid bullet scaffolds, or the old `### Final Delivery Summary` format.

Context you can reference (do **not** rewrite verbatim):

- **Tool recap**:

{{tool_summary}}

- **Plan markdown (read-only)**:

{{plan_markdown}}

Rules:

- If the plan is incomplete, be explicit about which checklist items remain.
- If no tools ran, say that this was explanation-only work.

- Never claim edits/tests that did not actually happen earlier in this run.

- Keep the entire response under 400 tokens—prioritize signal over fluff.
