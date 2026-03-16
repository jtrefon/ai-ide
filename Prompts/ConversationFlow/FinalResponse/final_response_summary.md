# Final Response Contract

{{followup_reason}}

Before returning the final answer:

1. If reasoning is needed, keep it terse and invisible to the user-facing summary. Do not emit controller-style schemas or scaffolded labels.
2. Follow with one terminal status sentence that states either completed work or the concrete blocker/remaining item. Do not use `Done → Next → Path` here.
3. Do **not** call tools during this stage. This is a summary only.

After the reasoning block, write a normal assistant reply in plain text.
State the result directly, mention verification only if it materially matters, and mention remaining work only if something is still unfinished or blocked.
Mention files only when they materially matter.
Do not use headings, report templates, rigid bullet scaffolds, or the old `### Final Delivery Summary` format.

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
