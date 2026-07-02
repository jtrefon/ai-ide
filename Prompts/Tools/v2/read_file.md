# read_file Tool

## Purpose
Read the contents of a file at the specified path. Supports reading specific line ranges with line numbers for precise navigation.

## When to Use
- Before modifying any file (the sandbox enforces read-before-write)
- Inspecting code, configs, or documentation
- Getting line numbers for patch_file edits
- Reading specific portions of large files instead of the entire content

## When NOT to Use
- Do NOT use for binary files (images, videos, archives)
- Do NOT use for extremely large files (>10MB) — use line ranges
- Do NOT use when you already know the content

## Parameters
- **path** (required, string): Absolute or project-relative path to the file.
- **start_line** (optional, integer): 1-based line to start reading from. Omit for line 1.
- **end_line** (optional, integer): 1-based line to read through (inclusive). Omit for EOF.
- **max_bytes** (optional, integer): Maximum bytes to read (default unlimited).

## Usage Examples
- Read entire file: `path: "src/main.swift"`
- Read lines 10-25: `path: "src/main.swift", start_line: 10, end_line: 25`
- Read single line: `path: "src/main.swift", start_line: 42, end_line: 42`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success" | "error"
- **message**: Summary like "Read file (150 lines, 4.2 KB)"
- **content.text**: File content. With line ranges, each line is prefixed: `LINE: CONTENT`
- **error.code**: FILE_NOT_FOUND | BINARY_FILE | FILE_TOO_LARGE
- **error.recoverable**: true | false
- **error.alternatives**: Suggested recovery actions

## Success Indicators
- status: "success" — file was read
- content.text contains the file content

## Error Handling
- FILE_NOT_FOUND: Use search_project to locate the file
- BINARY_FILE: Use run_command with the "file" command instead
- FILE_TOO_LARGE: Use start_line/end_line to read portions

## Best Practices
1. Always read before editing — the sandbox ENFORCES this
2. Use line ranges for large files instead of reading everything
3. Line numbers from read_file directly map to patch_file parameters
4. Multiple files can be read in the same turn
