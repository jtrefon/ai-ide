## edit — Edit an existing file by replacing a line range

**When to use:** ALL modifications to existing files. This is the primary mutation tool for single-line changes, multi-line blocks, or whole-function replacements. Use it (not `write`) when the file already exists and you only want to change part of it.

**Parameters:**
- path (required, string): Absolute or project-root-relative path to the file.
- start_line (required, integer): 1-based line where the replacement begins.
- end_line (required, integer): 1-based inclusive line where the replacement ends. Use the same value as start_line for a single-line edit.
- new_content (required, string): The text that replaces the lines start_line..end_line.

**Expected output:** Diff showing removed and added lines. Status confirmation.
status: success | error
content.text: diff output

**Common situations & recovery:**
- File not found: Create it with write instead.
- Line range invalid: Read the file again to get current line numbers.
