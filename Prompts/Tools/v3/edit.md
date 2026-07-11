## edit — Edit an existing file by replacing a line range

**When to use:** ALL modifications to existing files. This is the primary mutation tool. For single-line changes, multi-line blocks, or entire function replacements.

**Parameters:**
- path (required, string): Path to the file.
- start (required, integer): 1-based line where replacement begins.
- end (required, integer): 1-based line where replacement ends (inclusive). Use same as start for single-line edits.
- content (required, string): The replacement text for the specified line range.

**Expected output:** Diff showing removed and added lines. Status confirmation.
status: success | error
content.text: diff output

**Common situations & recovery:**
- File not found: Create it with write instead.
- Line range invalid: Read the file again to get current line numbers.
