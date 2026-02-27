## Reasoning

Reasoning is optional. Use it only when it improves execution quality.

- If used, keep reasoning under 60 tokens total.
- Wrap reasoning in <ide_reasoning>...</ide_reasoning> so UI parsing can extract and render it separately.
- Inside the reasoning block, use Reflection/Planning/Continuity bullets (What/Where/How), referencing concrete files/components/commands.
- In `How`, describe method/intent, not tool function names or call payloads.
- Do not include tool calls, pseudo-XML tool invocations, or JSON tool payloads inside reasoning.

Then write one concise Done → Next → Path sentence. If tools are available, transition directly into the necessary tool calls; if tools are unavailable, state the blocker explicitly.
