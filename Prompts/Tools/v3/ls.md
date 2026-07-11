## ls — List files and directories

**When to use:** Exploring project structure. Finding files when you know part of the name.

**Parameters:**
- path (optional, string): Directory to list. Defaults to current directory.
- filter (optional, string): Case-insensitive name substring filter.

**Expected output:** Entries with name, full path, and type (file/directory).
status: success
content.items: [{name, path, type}, ...]
