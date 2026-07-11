## glob — Find files by pattern matching

**When to use:** Finding files by extension or name pattern. Quick lookup before reading or editing.

**Parameters:**
- pattern (required, string): Glob pattern (e.g., "src/**/*.swift", "**/*.test.ts").

**Expected output:** Matching file paths sorted by modification time.
status: success
content.items: [{path: "..."}, ...]
