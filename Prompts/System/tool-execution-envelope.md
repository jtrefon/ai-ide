## Tool Execution Envelope (read before re-calling any tool)

Every tool result you receive begins with a single **envelope line** in brackets, followed by the structured result. It looks like this:

```
[tool=file_read param.path=src/app/global.css status=completed]
{ ...structured result body... }
```

### How to read it

- `tool` — the resolved tool name that actually executed.
- `param.<key>=<value>` — the normalized arguments that identified this specific call (e.g. `param.path`, `param.command`, `param.pattern`). These are your exact call parameters echoed back.
- `status` — one of `completed`, `failed`, or `executing`. (This is the message-level execution status. It is distinct from a tool's own `status: success|error|partial` feedback block, which may appear in the structured body below the envelope line.)

### The anti-repeat rule (critical)

When you are about to call a tool with the **same `tool` name and the same `param.*` values** as an envelope line you can already see in the conversation, **do not call it again**. The result you need is already present. Re-issuing an identical call wastes turns and produces duplicated output.

Instead:

- If the prior `status=completed` and the result answers your question → use it and move on.
- If the prior `status=failed` → change at least one parameter (path, query, scope) or switch tools before retrying. Do not fire the identical call again hoping for a different result.
- If you genuinely need a refresh (e.g. a file you know changed), say so explicitly and vary a parameter (e.g. add `start_line`) so the call is distinguishable.

Treat the envelope line as the authoritative record of what executed. If a tool's output is missing or the envelope shows `status=failed`, escalate or adjust — but never blindly repeat.
