# Tool: find_file

WHAT: Finds files by filename (case-insensitive substring match) within the project.

WHEN: Use when you know the filename but not its full path. Faster than list_files + manual scanning through directories.

HOW:
- query (required, string): The filename to search for. Case-insensitive substring match.
- path (optional, string): Directory to restrict the search to. Defaults to project root.
- Overloading: Use the exact filename for precise results. Use a substring to find related files (e.g., "network" finds NetworkManager, NetworkService, etc.).

OUTPUT: Returns the full paths of all matching files.
