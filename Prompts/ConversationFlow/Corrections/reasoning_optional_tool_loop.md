## Reasoning

During tool loop execution, keep reasoning optional and compact:

- If reasoning is needed, keep it under 60 tokens total.
- If reasoning is needed, keep it as short plain text using Reflection/Planning/Continuity bullets and never include tool calls or JSON tool payloads.
- In `How`, describe implementation intent or method, not tool function names.
- Write one concise Done → Next → Path sentence.
- Immediately return tool calls that implement the Planning intent.
- No filler, no repeated blocks, no pseudo-tool JSON.
