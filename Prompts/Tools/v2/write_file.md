# write_file Tool

## Purpose

Create a new file with the given content, or overwrite an existing file entirely. For editing existing files, ALWAYS prefer patch_file instead.

## When to Use

- Creating NEW files that don't exist yet
- Initial project scaffolding (creating multiple new files)
- Generating boilerplate code, config files, or assets

## When NOT to Use

- Do NOT use for editing EXISTING files — use patch_file instead
- Do NOT use when only a few lines need to change — patch_file is more efficient

## Parameters

- **path** (required, string): Absolute or project-relative path for the file.
- **content** (required, string): The full content to write to the file.
- **mode** (optional, string): "apply" (default, writes immediately) or "propose" (stages for review).

## Usage Examples

- Create new file: `{ "path": "src/utils.ts", "content": "export function add(a: number, b: number) { return a + b; }" }`
- Propose changes: `{ "path": "src/config.json", "content": "{...}", "mode": "propose" }`

## Output Structure

Returns a ToolFeedback envelope:

- **status**: "success" | "error"
- **message**: "Created src/utils.ts (45 bytes)"
- **error.code**: PATH_OUTSIDE_SANDBOX | MUTATION_WITHOUT_PRIOR_READ

## Success Indicators

- status: "success" — file was written
- message includes byte count

## Error Handling

- MUTATION_WITHOUT_PRIOR_READ: For EXISTING files, use patch_file. For new files, ensure the file doesn't exist.

## Best Practices

1. ONLY use for creating new files
2. For edits to existing files, use patch_file
3. Read the file first if you're unsure whether it exists
