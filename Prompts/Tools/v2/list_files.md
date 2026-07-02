# Tool: list_files

WHAT: Lists files and directories at a given path with optional name filtering and limit.

WHEN: Use to explore the project structure, find files by name pattern, or discover what exists in a directory before reading or editing.

HOW:
- path (optional, string): Directory to list. Defaults to project root when omitted.
- query (optional, string): Case-insensitive filename substring filter. Only entries matching this will be returned.
- limit (optional, int, 1-1000): Maximum number of entries to return. Default unlimited.
- Overloading: Omit path to explore root. Add query to find specific files. Add limit to avoid overwhelming output in large directories.

OUTPUT: Returns a list of file and directory paths with their types. Vendor/dependency directories are marked as (excluded).
