## search — Search the codebase for code: symbols, text, filenames

**When to use:** FIRST tool for ANY code discovery. Finding where a function, class, or variable is defined or used. Locating files when you know what they contain but not their name.

**Parameters:**
- query (required, string): The code or text to search for.
- max_results (optional, integer): Max results (default 20, max 100).

**Expected output:** Matches grouped by file with line numbers, match type, and context snippet.
status: success
content.items: [{path, line, kind, context}, ...]
message: "Found N matches in M files"

**Common situations & recovery:**
- No results: Try a broader query, or part of the name.
