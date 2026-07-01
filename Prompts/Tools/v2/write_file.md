# write_file Tool

## Purpose
Write content to a file. Creates the file if it doesn't exist. Overwrites if it does.

## Parameters
- **path** (required, string): Absolute or project-root-relative path to the file.
- **content** (required, string): Complete file content to write.
- **mode** (optional, string): "apply" (default, writes immediately) or "propose" (stages for review).

## Feedback Format

**Success (new file):**
```
status: success
message: "Created file src/main.swift (245 bytes, 42 lines)"
```

**Success (overwrite):**
```
status: success
message: "Updated file src/main.swift (overwrote existing, 245 bytes)"
```

**Error (no prior read):**
```
status: error
message: "Cannot write to src/main.swift: you must read it first"
error:
  code: MUTATION_WITHOUT_PRIOR_READ
  recoverable: true
  alternatives:
    - description: "Read the file first"
      suggestion: "read_file(path: \"src/main.swift\")"
      toolName: "read_file"
      arguments:
        path: "src/main.swift"
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `MUTATION_WITHOUT_PRIOR_READ` | Must read before writing existing file | Read the file first |
| `FILE_NOT_FOUND` (write to subdirectory) | Parent directory doesn't exist | Create parent directory first |
| `PATH_OUTSIDE_SANDBOX` | Path outside project root | Use project-relative path |
| `PERMISSION_DENIED` | No write access | Check file permissions |

## Rules

1. **New files**: No prior read required. Write freely.
2. **Existing files**: You MUST read the file before writing to it. This is ENFORCED by the sandbox.
3. **Read-before-write** is tracked per conversation turn. A read from a previous turn does not count.
4. **Complete content**: Provide the full file content, not a diff.

## When to Use

- Creating new files
- Complete file rewrites
- Scaffolding project structures

## When NOT to Use

- Small edits to existing files → use `replace_in_file` or `patch_file`
- Creating multiple related files → use `write_files` (multi-file variant)
