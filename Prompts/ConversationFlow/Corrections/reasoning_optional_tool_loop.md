## Reasoning

During tool loop execution, keep reasoning optional and compact:

- If reasoning is needed, keep it under 80 tokens total.
- Wrap reasoning in <ide_reasoning>...</ide_reasoning> so UI parsing can extract and render it separately.
- Inside the reasoning block, use Reflection/Planning/Continuity bullets and never include tool calls, pseudo-XML, or JSON tool payloads.
- Write one concise Done → Next → Path sentence.
- Immediately return tool calls that implement the Planning How/Where instructions.
- No filler, no repeated blocks, no pseudo-tool JSON.

Compact example:
<ide_reasoning>
Reflection:
- What: <result>
- Where: <file/component>
- How: <tool/operation>
Planning:
- What: <next objective>
- Where: <exact locus>
- How: <tool/action>
Continuity: <risks/invariants>
</ide_reasoning>
Hardened X in File.swift; next adjust Tests.swift via write_file.
