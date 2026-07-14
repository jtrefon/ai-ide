## ls — List files and directories

**When to use:** Exploring project structure. Finding files when you know part of the name.

**Parameters:**
- path (optional, string): Directory to list. Defaults to current directory.
- filter (optional, string): Case-insensitive name substring filter.

**Expected output:** Plain text, one entry per line — the name of each file or directory (with ` (excluded)` appended when filtered out). For full paths use `glob`.
Example:
```
src
index.html
package.json (excluded)
```
Read the list directly from the text. There is no nested JSON `content.items` field.
