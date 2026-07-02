# search_project Tool

## Purpose

THE PRIMARY code search tool. Searches for classes, functions, variables, files, and text patterns across the entire project using a multi-tier strategy: filename matching, symbol lookup, and text search.

## When to Use

- FIRST tool for ANY code search — faster than manually reading files
- Finding where a function/class/variable is defined or used
- Checking if similar code already exists before writing new code
- Locating files when you know what they contain but not their name

## When NOT to Use

- Do NOT use for file system exploration — use list_files instead
- Do NOT use for exact filename lookup — use find_file instead

## Parameters

- **query** (required, string): The text, code, or symbol name to search for.

## Usage Examples

- Search function: `{ "query": "NetworkManager" }`
- Search pattern: `{ "query": "func handle" }`

## Output Structure

Returns a ToolFeedback envelope:

- **status**: "success"
- **content.items[]**: Array of matches with file path, line number, and context snippet
- **message**: "Found 5 matches in 3 files"

## Success Indicators

- content.items contains search results with context

## Best Practices

1. Use this FIRST before any other search tool
2. Use specific names (function names, class names) for best results
