# Tool: search_project

WHAT: THE PRIMARY search tool for finding code. Searches classes, functions, variables, files, and text patterns across the project.

WHEN: Use as the FIRST step for ANY code search task. Faster than manually reading multiple files. Use before creating new code to check if similar functionality already exists.

HOW:
- query (required, string): The text or code pattern to search for.
- Overloading: Use specific terms (function names, class names, variable names) for best results. Supports fuzzy matching for partial names.

OUTPUT: Returns matching code locations with file paths, line numbers, and context snippets.
