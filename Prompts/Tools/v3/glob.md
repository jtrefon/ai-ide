## glob — Find files by pattern matching

**When to use:** Finding files by extension or name pattern. Quick lookup before reading or editing.

**Parameters:**
- pattern (required, string): Glob pattern (e.g., "src/**/*.swift", "**/*.test.ts").

**Expected output:** Plain text. A header `Found N file(s):` followed by one matching file path per line, sorted by modification time.
Example:
```
Found 2 file(s):
src/App.tsx
src/main.ts
```
Read the paths directly from the text. There is no nested JSON `content.items` field.
