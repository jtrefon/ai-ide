Retry context:
- Attempt: {{attempt}}/{{max_attempts}}
- Reason for retry: {{retry_reason}}
- Keep the same user goal and conversation context.
- Do not repeat the same failed action unchanged.
- If tools are needed, provide a concise progress update (completed step + next step + how), then return tool calls.
