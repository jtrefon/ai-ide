# Write Files Tool

## Purpose
Write content to multiple files in a single operation. This is the PREFERRED tool for scaffolding projects, creating new file structures, or making coordinated multi-file changes.

## When to Use
- **Project Scaffolding**: Creating new applications with multiple files (React apps, Node.js projects, etc.)
- **Multi-file Operations**: When you need to create/modify several related files simultaneously
- **Coordinated Changes**: When files need to be created together to maintain consistency
- **Initial Setup**: Setting up configuration files, entry points, and component files

## When NOT to Use
- **Single File Edits**: Use `replace_in_file` for editing existing files
- **Small Changes**: Use `write_file` for single file operations
- **Appending**: This tool overwrites files completely

## Parameters
- **files** (required, array): List of files to write
  - **path** (required, string): File path (absolute or project-root-relative)
  - **content** (required, string): Complete file content
- **mode** (optional, string): File write mode (default: "overwrite")
- **patch_set_id** (optional, string): For patch tracking

## Usage Examples

### Basic Project Scaffolding
```json
{
  "files": [
    {
      "path": "package.json",
      "content": "{\n  \"name\": \"my-app\",\n  \"version\": \"1.0.0\"\n}"
    },
    {
      "path": "src/index.js",
      "content": "console.log('Hello World');"
    }
  ]
}
```

### React Application Setup
```json
{
  "files": [
    {
      "path": "package.json",
      "content": "// React package.json with dependencies"
    },
    {
      "path": "index.html",
      "content": "// HTML entry point"
    },
    {
      "path": "src/main.jsx",
      "content": "// React main component"
    },
    {
      "path": "src/App.jsx",
      "content": "// App component"
    }
  ]
}
```

## Output Structure
```json
{
  "status": "completed",
  "message": "Successfully wrote 4 files",
  "payload": {
    "files_written": ["package.json", "index.html", "src/main.jsx", "src/App.jsx"],
    "total_bytes": 1234
  },
  "toolName": "write_files",
  "toolCallId": "call_123"
}
```

## Success Indicators
- All files specified in the `files` array are created/overwritten
- File content matches exactly what was provided
- Directory structure is created if needed
- No permission errors or path conflicts

## Error Handling
- **Permission Denied**: Check file permissions and directory access
- **Invalid Path**: Verify path syntax and directory existence
- **Disk Full**: Check available disk space
- **Path Conflicts**: Existing files may be overwritten (mode="overwrite")

## Best Practices
1. **Group Related Files**: Create logically related files together
2. **Verify Paths**: Ensure all paths are valid and accessible
3. **Complete Content**: Provide full file content, not partial
4. **Directory Structure**: Include all necessary directories in paths
5. **File Extensions**: Use correct extensions for file types

## Integration Notes
- Automatically creates parent directories if they don't exist
- Overwrites existing files by default
- Atomic operation - either all files succeed or none are written
- Preserves file permissions and creates with default permissions
