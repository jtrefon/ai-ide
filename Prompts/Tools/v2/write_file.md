# Tool: write_file

WHAT: Creates a new file or overwrites an existing one with the given content.

WHEN: Use ONLY for creating NEW files. For editing EXISTING files, ALWAYS use patch_file instead — it is more efficient (sends only changed lines) and preserves context.

HOW:
- path (required, string): Absolute or project-relative path for the file.
- content (required, string): The full content to write to the file.
- mode (optional, string): "apply" (default, writes immediately) or "propose" (stages for review without applying).
- Overloading: For new files, use mode="apply". For sensitive changes, use mode="propose" to preview first.

OUTPUT: Returns a success message confirming the file was written, including the file size in bytes.
