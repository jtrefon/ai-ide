## Reasoning

During tool loop execution, keep reasoning optional and compact:

- If reasoning is needed, keep it under 60 tokens total.
- Wrap reasoning in <ide_reasoning>...</ide_reasoning> so UI parsing can extract and render it separately.
- Inside the reasoning block, use Reflection/Planning/Continuity bullets and never include tool calls, pseudo-XML, or JSON tool payloads.
- In `How`, describe implementation intent or method, not tool function names.
- Write one concise Done → Next → Path sentence.
- Immediately return tool calls that implement the Planning intent.
- No filler, no repeated blocks, no pseudo-tool JSON.

Compact example:
<ide_reasoning>
Reflection:
- What: <result>
- Where: <file/component>
- How: <method/approach>
Planning:
- What: <next objective>
- Where: <exact locus>
- How: <next implementation intent>
Continuity: <risks/invariants>
</ide_reasoning>
Hardened X in File.swift; next adjust Tests.swift via write_file.
