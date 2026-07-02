# Tool: read_file

WHAT: Reads the content of a file at the given path. Supports reading specific line ranges with optional line numbers.

WHEN: Use BEFORE modifying any file — the sandbox enforces read-before-write. Use to inspect code, read documentation, check file contents, or get line numbers for patch_file edits. When exploring an unknown codebase, start with list_files then read_file on relevant files.

HOW:
- path (required, string): Absolute or project-relative path to the file.
- start_line (optional, int): 1-based line to start reading from. Omit to start at line 1.
- end_line (optional, int): 1-based line to read through (inclusive). Omit to read to end of file.
- Overloading: omit both start/end_line to read entire file; set both to read a range; set both equal to read one line.

OUTPUT: Returns the file content. When using line ranges, lines are prefixed with line numbers (e.g., `42: private let session`). Full file reads return raw content.
