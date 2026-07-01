# read_file Tool

## Purpose
Read the contents of a file. Returns line-numbered content. Always use this before modifying an existing file.

## Parameters
- **path** (required, string): Absolute or project-root-relative path to the file.
- **start_line** (optional, integer): 1-based line number to start reading from. Use to read specific sections.
- **end_line** (optional, integer): 1-based line number to read through (inclusive). Omit to read to end of file.
- **max_bytes** (optional, integer): Maximum bytes to read (default 5MB). Use for large files.

## Feedback Format

```
status: success
message: "Read NetworkManager.swift (42 lines, 1,024 bytes)"
content:
  data:
    text: |
      1: import Foundation
      2: 
      3: class NetworkManager {
      4:     private let session: URLSession
      ...
  metadata:
    lineCount: "42"
    byteCount: "1024"
    path: "src/network/NetworkManager.swift"
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `FILE_NOT_FOUND` | File doesn't exist | Use search_project to find it |
| `PATH_OUTSIDE_SANDBOX` | Path outside project | Use project-relative path |
| `BINARY_FILE` | File is binary, can't read as text | Use different approach |
| `FILE_TOO_LARGE` | Exceeds max_bytes | Read specific line range instead |

## Best Practices

1. **Read before write**: Always read a file before modifying it. The sandbox ENFORCES this — writes to unread files will fail.
2. **Line ranges**: For large files, use start_line/end_line to read only what you need.
3. **Line numbers**: Read output includes line numbers. Use these when calling replace_in_file or patch_file.
4. **Multiple reads**: You can read multiple files. Independent reads run in parallel.
