# list_files Tool

## Purpose
List files and directories in a specified directory. Returns a structured listing with file names, types, and sizes.

## Parameters
- **path** (required, string): Absolute or project-root-relative path to the directory to list.
- **recursive** (optional, boolean): If true, list all files recursively (default: false).
- **max_results** (optional, integer): Maximum items to return (default 100, max 500).

## Feedback Format

```
status: success
message: "Listed 12 items in src/network/"
content:
  data:
    items:
      - label: "NetworkManager.swift"
        kind: "file"
        path: "src/network/NetworkManager.swift"
      - label: "NetworkError.swift"
        kind: "file"
        path: "src/network/NetworkError.swift"
      - label: "Models"
        kind: "directory"
        path: "src/network/Models"
  metadata:
    totalItems: "12"
    path: "src/network/"
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `FILE_NOT_FOUND` | Directory doesn't exist | Use search_project to find it |
| `PATH_OUTSIDE_SANDBOX` | Path outside project | Use project-relative path |

## Best Practices

1. **Non-recursive first**: Use `recursive: false` to explore directory structure, then drill down.
2. **Project root**: Use `.` or empty path to list the project root.
3. **Vendor exclusion**: Vendor/dependency directories are automatically excluded from results.
