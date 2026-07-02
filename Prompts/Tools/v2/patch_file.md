# Tool: patch_file

WHAT: Replaces a range of lines in an existing file with new content. This is the PREFERRED way to edit files — surgical, precise, and context-efficient.

WHEN: Use for ALL edits to existing files. Do NOT use write_file for edits — patch_file sends only the changed lines instead of the entire file, keeping context smaller and operations faster.

HOW:
- path (required, string): Absolute or project-relative path to the file to edit.
- start_line (required, int): 1-based line where replacement begins.
- end_line (required, int): 1-based line where replacement ends (inclusive). Set equal to start_line for single-line edits.
- new_content (required, string): The replacement content for the specified line range.
- Overloading: For single-line edits, set start_line = end_line. For multi-line blocks, set the range to encompass the entire block being replaced. Read the file first with read_file to get exact line numbers.

OUTPUT: Returns a diff-like confirmation showing what changed (lines removed and added).
