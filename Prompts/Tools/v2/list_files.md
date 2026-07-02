# list_files Tool

## Purpose
List files and directories under a project path with optional name filtering and result limiting.

## When to Use
- Exploring project structure before reading or editing files
- Finding files by name pattern
- Understanding directory layout

## When NOT to Use
- Do NOT use to search file contents — use search_project or grep instead
- Do NOT use when you know the exact filename — use find_file instead

## Parameters
- **path** (optional, string): Directory to list. Defaults to project root.
- **query** (optional, string): Case-insensitive filename substring filter.
- **limit** (optional, integer, 1-1000): Maximum entries to return.

## Usage Examples
- List root: `{}` or `{ "path": "." }`
- Find specific files: `{ "query": "network" }` — lists only files with "network" in name
- Limit output: `{ "path": "src", "limit": 20 }`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success"
- **content.items[]**: Array of entries with name, path, type (file/directory)
- **message**: "Found 15 entries"

## Success Indicators
- content.items contains directory listing

## Best Practices
1. Use query to filter large directories
2. Vendor directories are marked (excluded) to keep output manageable
