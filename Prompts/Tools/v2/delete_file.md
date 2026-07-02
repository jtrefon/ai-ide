# delete_file Tool

## Purpose
Delete a file or empty directory at the specified path.

## When to Use
- Removing files that are no longer needed
- Cleaning up temporary or generated files
- Removing old versions before creating replacements

## When NOT to Use
- Do NOT use for non-empty directories (delete files individually first)

## Parameters
- **path** (required, string): Absolute or project-relative path to delete.

## Usage Examples
- `{ "path": "src/old-file.ts" }`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success" | "error"
- **message**: Confirmation of deletion
- **error.code**: FILE_NOT_FOUND | DIRECTORY_NOT_EMPTY

## Success Indicators
- status: "success"

## Error Handling
- FILE_NOT_FOUND: File doesn't exist — already removed or wrong path
- DIRECTORY_NOT_EMPTY: Delete files inside first
