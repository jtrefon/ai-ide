# patch_file Tool

## Purpose

Apply a targeted edit to an existing file by replacing a range of lines. This is the PREFERRED way to edit files — surgical, precise, and context-efficient. Does NOT require exact text matching (unlike replace_in_file).

## When to Use

- ALL edits to existing files. This is the PRIMARY mutation tool.
- Adding new code blocks between existing lines
- Replacing specific functions, methods, or sections
- Single-line changes like variable renames or import additions

## When NOT to Use

- Do NOT use write_file for existing files — patch_file is always better
- Do NOT use for creating NEW files — use write_file instead
- Do NOT guess line numbers — always read the file first

## Parameters

- **path** (required, string): Absolute or project-relative path to the file.
- **start_line** (required, integer): 1-based line where replacement begins.
- **end_line** (required, integer): 1-based inclusive line where replacement ends. Set = start_line for single-line edits.
- **new_content** (required, string): The replacement content for the specified line range.

## Usage Examples

- Replace single line: `{ "path": "src/main.swift", "start_line": 5, "end_line": 5, "new_content": "let name = \"John\"" }`
- Replace function body: `{ "path": "src/app.tsx", "start_line": 10, "end_line": 25, "new_content": "// new implementation" }`
- Add lines after position: set start_line = end_line = insertion point, new_content includes the new lines

## Output Structure

Returns a ToolFeedback envelope:

- **status**: "success" | "error"
- **message**: Summary of changes applied
- **content.text**: Diff-like output showing removed (---) and added (+++) lines
- **error.code**: FILE_NOT_FOUND | INVALID_LINE_RANGE | MUTATION_WITHOUT_PRIOR_READ
- **error.recoverable**: true | false
- **error.alternatives**: Recovery suggestions

## Success Indicators

- status: "success" — edit was applied
- content.text shows the diff

## Error Handling

- FILE_NOT_FOUND: File doesn't exist. Use write_file to create it.
- INVALID_LINE_RANGE: Line numbers out of range. Read the file again.
- MUTATION_WITHOUT_PRIOR_READ: You must read the file before editing it. Call read_file first.

## Best Practices

1. ALWAYS read the file first to get accurate line numbers
2. For single-line edits, keep start_line == end_line
3. For multi-line blocks, set the range to encompass the entire replaced block
4. Use the line-numbered output from read_file to determine exact line numbers
