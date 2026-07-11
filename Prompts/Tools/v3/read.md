## read — Read file contents with optional line range

**When to use:** Before editing any file. Inspecting code, configs, or docs. Getting line numbers for edit calls.

**Parameters:**
- path (required, string): Path to the file.
- start (optional, integer): 1-based start line. Omit for line 1.
- end (optional, integer): 1-based end line (inclusive). Omit for EOF.

**Expected output:** File content with line numbers. Line count and size in status.
status: success | error
content.text: file content (line-numbered when using start/end)

**Common situations & recovery:**
- File not found: Use search or glob to locate it first.
- File is large: Use start/end to read only the range you need. The line numbers map directly to edit parameters.
