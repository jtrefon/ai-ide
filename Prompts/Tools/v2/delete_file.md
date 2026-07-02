# Tool: delete_file

WHAT: Deletes a file or empty directory at the specified path.

WHEN: Use to remove files that are no longer needed, clean up temporary files, or remove generated artifacts.

HOW:
- path (required, string): Absolute or project-relative path to the file or empty directory to delete.
- Overloading: Only deletes files or EMPTY directories. For non-empty directories, delete files individually first.

OUTPUT: Returns a success message confirming the file was deleted.
