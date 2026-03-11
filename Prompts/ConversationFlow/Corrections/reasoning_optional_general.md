## Reasoning

Reasoning is optional. Use it only when it improves execution quality.

- If used, keep reasoning under 60 tokens total.
- If used, keep it as short plain text using Reflection/Planning/Continuity bullets (What/Where/How), referencing concrete files/components/commands.
- In `How`, describe method/intent, not tool function names or call payloads.
- Do not include tool calls or JSON tool payloads inside reasoning.

Then write one concise Done → Next → Path sentence. If tools are available, transition directly into the necessary tool calls; if tools are unavailable, state the blocker explicitly.
