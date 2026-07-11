# Tool Feedback Format (Universal Contract)

Every tool returns feedback in this structure.

## Structure

```
status: success | error | partial
message: Human-readable summary
content: Present for query tools (read, search, ls, glob, context, web_search, web_fetch). Null for mutation tools.
error:
  code: MACHINE_READABLE_CODE
  recoverable: true
  alternatives:
    - description: "What to do"
```

## Common Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| FILE_NOT_FOUND | Path does not exist | Use search or glob to locate |
| LINE_RANGE_INVALID | Line numbers out of range | Read file again |
| READ_BEFORE_WRITE | Must read before editing | Call read on the file first |
| COMMAND_FAILED | Non-zero exit | Check stderr in output |
