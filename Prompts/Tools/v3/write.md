## write — Create a new file or overwrite an existing one

**When to use:** Creating NEW files. For edits to existing files, use edit instead.

**Parameters:**
- path (required, string): Path for the new file.
- content (required, string): The full content to write.

**Expected output:** Status confirmation with byte count.
status: success | error
message: "Created path/to/file (123 bytes)"

**Common situations & recovery:**
- File already exists with important content: Use edit to make targeted changes instead.
