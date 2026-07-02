# find_file Tool

## Purpose
Find files by name using case-insensitive substring matching across the project.

## When to Use
- When you know the filename but not its full path
- Quick lookup before reading or editing a file

## When NOT to Use
- Do NOT use for searching file CONTENTS — use search_project instead
- Do NOT use for exploring directory structure — use list_files instead

## Parameters
- **query** (required, string): Filename to search for (case-insensitive substring match).
- **path** (optional, string): Directory to restrict the search to. Defaults to project root.

## Usage Examples
- `{ "query": "NetworkManager" }` — finds NetworkManager.swift, NetworkManagerTest.swift, etc.
- `{ "query": "config", "path": "src" }`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success"
- **content.items[]**: Full file paths matching the query
- **message**: "Found 3 files"

## Success Indicators
- content.items contains matching file paths
