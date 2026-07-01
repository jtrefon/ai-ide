# Tool Feedback Format (Universal Contract)

Every tool returns feedback in this structure. The model (you) should always expect this format — never raw strings, never ad-hoc formatting.

## Structure

```
status: [success | error | partial]
message: Human-readable summary (1-2 lines)
content: Present for query tools (search, read, list). Null for command tools.
error: Present on failure. Contains error code and suggested recovery alternatives.
```

## Status Values

| Value | Meaning | When |
|-------|---------|------|
| `success` | Tool completed as expected | File read, file written, search results |
| `error` | Tool failed | File not found, permission denied, blocked |
| `partial` | Partial success | 3/5 files written, 2 failed |

## Content (Query Tools)

Query tools (read_file, search_project, list_files, web_search) include a `content` field:

```
content:
  data:
    text: "Raw text content (file contents, page text, etc.)"
    # OR
    items:                              # Structured list
      - label: "NetworkManager"
        kind: "class"
        path: "src/network/NetworkManager.swift"
        lineNumber: 1
  metadata:
    totalResults: "3"
    byteCount: "245"
```

## Error Codes (Recovery)

When a tool fails, the `error` field contains:

```
error:
  code: MUTATION_WITHOUT_PRIOR_READ    # Machine-readable error code
  message: "You must read this file before modifying it."
  recoverable: true                     # True = retry with different approach
  alternatives:                         # Suggested recovery paths
    - description: "Read the file first"
      suggestion: "read_file(path: \"src/main.swift\")"
      toolName: "read_file"
```

### Common Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `FILE_NOT_FOUND` | Path does not exist | Check path, use search_project to find it |
| `PERMISSION_DENIED` | No read/write access | Check file permissions |
| `PATH_OUTSIDE_SANDBOX` | Path is outside project root | Use path relative to project root |
| `MUTATION_WITHOUT_PRIOR_READ` | Must read before writing | Read the file first, then retry |
| `FILE_ALREADY_EXISTS` | Cannot create, file exists | Use write_file to overwrite, or replace_in_file to edit |
| `RESOURCE_BUSY` | File is locked by another process | Wait briefly, or use terminal command to force |
| `INVALID_ARGUMENT` | Missing or malformed parameter | Check required parameters |
| `NETWORK_TIMEOUT` | Web request timed out | Retry with simpler query |
| `SEARCH_BLOCKED` | Search engine blocked request | Try a different query or use web_browse with a URL |
| `INDEX_NOT_AVAILABLE` | Codebase index is still building | Wait a moment, or use fallback search |

## Recovery Pattern

When you see `error.recoverable: true` AND `error.alternatives` is not empty:

1. Read the alternatives
2. Pick the most promising one (usually the first)
3. Execute the alternative tool call
4. Do NOT retry the same call with the same arguments

When `error.recoverable: false`:
- Report the error to the user
- Do NOT retry
- Suggest an alternative approach if possible
