# search_project Tool

## Purpose
THE PRIMARY search tool for ANY code search task. Finds classes, functions, variables, files, and text patterns using a multi-tier search system. Always use this first before grep, find_file, or any other search tool.

## Parameters
- **query** (required, string): The search term. Case-insensitive. Can be a class name, function name, variable name, file name, or any text pattern.
- **max_results** (optional, integer): Maximum results to return (default 50, max 200).

## Search Tiers (automatic)

The tool runs multiple search methods and combines results:

1. **File name match** (<1ms): Matches the query against all file paths in the project.
2. **Full-text index** (1-5ms): Searches indexed file contents via FTS5.
3. **Symbol lookup** (5-10ms): Finds classes, structs, functions, protocols by name.
4. **Semantic search** (10-50ms): Vector similarity search for conceptually related code.
5. **Filesystem grep** (50-200ms): Fallback raw text search. Only used if index is unavailable.

The tool stops early if enough high-quality results are found in lower tiers.

## Feedback Format

```
status: success
message: "Found 3 matches for 'NetworkManager' in 2 files"
content:
  data:
    items:
      - label: "class NetworkManager"
        kind: "class"
        path: "src/network/NetworkManager.swift"
        lineNumber: 1
      - label: "let networkManager"
        kind: "variable"
        path: "src/AppDelegate.swift"
        lineNumber: 14
      - label: "NetworkManagerDelegate"
        kind: "protocol"
        path: "src/network/NetworkManager.swift"
        lineNumber: 87
  metadata:
    totalResults: "3"
    queryTimeMs: "12"
```

**No results:**
```
status: success
message: "No matches found for 'NetwrkManager'"
content:
  metadata:
    totalResults: "0"
    suggestion: "Did you mean 'NetworkManager'?"
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `INDEX_NOT_AVAILABLE` | Index still building | Wait and retry, or use grep directly |
| `QUERY_TOO_SHORT` | Query must be at least 2 characters | Expand the query |

## Best Practices

1. **Always use this first**: Before grep, find_file, or any other search tool. This is the most comprehensive search.
2. **Be specific**: Class names, exact file names, and function names give the best results.
3. **Use results for reading**: After search_project finds files, use read_file to view specific matches.
4. **Check spelling**: If results are empty, check for typos in your query. The tool does not auto-correct.
