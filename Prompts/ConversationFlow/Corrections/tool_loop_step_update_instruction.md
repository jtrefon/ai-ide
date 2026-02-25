Before returning tool calls, always emit the following in order:

1. **Structured reasoning block** inside `<ide_reasoning>`:

    ```text
    <ide_reasoning>
    Reflection:
    - What: <single-clause summary of the most recent result or blocker>
    - Where: <specific file/function/component touched>
    - How: <tool, technique, or approach used>
    Planning:
    - What: <next target or objective>
    - Where: <exact locus for the next change>
    - How: <tool/action you will apply>
    Continuity: <risks, invariants, or context to carry forward>
    </ide_reasoning>
    ```

    - Use terse, technical language—no filler such as “just finished” or “planning to.”
    - Each bullet must be a single clause that names concrete artifacts (e.g., `ToolLoopHandler.swift – enforce dropout guard`).
    - If the previous step failed, capture the blocker in Reflection/Continuity and show how the plan adapts.

2. **Condensed pair-programmer update sentence** immediately after the reasoning block. Follow the `Done → Next → Path` arc in one sentence, e.g., “Hardened dropout guard in ToolLoopHandler.swift; next wire ToolLoopDropoutHarnessTests.swift via failure injection.” Keep it dense but readable.

    - Keep the update to one sentence that covers `Done → Next → Path`.
    - Do not restate every bullet from the reasoning block; summarize only the most important context.

3. **Tool calls** for the upcoming step. Ensure actions match the Planning section and do not ask the user for more input.

    - Tool invocations must correspond to the “Planning” How/Where pairing.
    - Never pause for user confirmation during the tool loop.

### Example

```text
<ide_reasoning>
Reflection:
- What: Tightened dropout guard
- Where: ToolLoopHandler.swift – executePhase()
- How: Inserted early-return when no tool calls
Planning:
- What: Validate dropout handling
- Where: ToolLoopDropoutHarnessTests.swift
- How: Expand failure-injection harness
Continuity: Watching cache pressure after repeated retries
</ide_reasoning>
Locked in the dropout guard; next extend ToolLoopDropoutHarnessTests.swift with failure injection to prove the path.
```
