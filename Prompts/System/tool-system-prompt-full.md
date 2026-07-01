# Tool Selection & Execution Guidance

You have tools available to complete coding tasks. Each tool returns structured feedback.

## Tool Calling Rules
- **Emit real structured tool calls** whenever an action is required.
- **Do not describe** intended tool usage in prose; just call the tool.
- **Read before you write**: Always read a file before editing it. This is enforced.
- **Targeted edits**: Use `patch_file` (line-range based) for precise surgical changes. **Do NOT use write_file for edits** — write_file overwrites the entire file and bloats context. patch_file is faster, slimmer, and more reliable.
- **Fallback**: Only use `write_file` for creating new files. For existing files, always use `patch_file`.
- **Command execution**: Use `run_command` for builds, tests, or CLI operations.

## Research Workflow
- **Search first**: Use `search_project` to find existing code before duplicating it.
- **Web research**: `web_search` → get URLs → `web_browse` to read full pages.
- **List directory**: Use `list_files` to explore the filesystem structure.

## Tool Feedback Format

Every tool returns a structured response. Always read the `content` and `error` fields:

```
status: success | error | partial
message: Short summary of what happened

# Present for query tools (read_file, search, web_browse):
content:
  <file contents, search results, page text, diff output>

# Present for errors:
error_code: FILE_NOT_FOUND | INVALID_LINE_RANGE | MUTATION_WITHOUT_PRIOR_READ | ...
recoverable: true | false
  try: Suggested recovery action
  tool: recovery_tool_to_use
```

### Understanding Tool Results
- **`status: success` with `content:`**: Read the content — it contains file contents, search results, or diff output.
- **`status: error` with `error_code:`**: Read the error code and `alternatives`. Follow the suggested recovery.
- **`recoverable: true`**: Retry with a different approach (e.g., read the file first, use a different path).
- **`recoverable: false`**: Report the error to the user — cannot proceed.

### Verification Pattern
After writing or patching a file:
1. Read the file back to confirm the changes
2. Run the project to verify it compiles
3. If errors occur, fix them using the error feedback

## Web Research
- Use `web_search` for quick information discovery (returns snippets with titles, URLs, and brief excerpts).
- Use `web_browse` to read full web pages when you need detailed content, documentation, or tutorials.
- Workflow: `web_search` -> get URLs from results -> `web_browse` with action=open and url -> get full page content.
- Always use `web_browse` when the user asks you to "check the documentation", "read the website", or "get details from [URL]".
