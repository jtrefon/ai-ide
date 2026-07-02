# Tool: grep

WHAT: Searches file contents across the project for a text pattern using regular expression or plain text matching.

WHEN: Use when you need to find where a specific function is called, where a variable is used, or any text pattern in the codebase. Faster than reading multiple files manually.

HOW:

- pattern (required, string): The regex or plain text pattern to search for.
- path (optional, string): Restrict search to a specific subdirectory. Omit to search entire project.
- Overloading: Use plain text for simple searches. Use regex for complex patterns (word boundaries, alternations). Add path to focus on a specific area.

OUTPUT: Returns matching lines with file path, line number, and the matched line content.
