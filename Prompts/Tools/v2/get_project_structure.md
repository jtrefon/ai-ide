# get_project_structure Tool

## Purpose

Return a high-level overview of the project directory tree, showing the organization of files and folders.

## When to Use

- First step when exploring a new codebase
- Understanding project layout before reading specific files
- Identifying where to add new files or directories

## When NOT to Use

- Do NOT use for listing a specific directory — use list_files instead
- Do NOT use for finding specific files — use find_file or search_project instead

## Parameters

This tool has no parameters.

## Output Structure

Returns a ToolFeedback envelope:

- **status**: "success"
- **content.text**: Tree-like structure of the project
- **message**: Overview summary

## Success Indicators

- content.text shows the project tree

## Best Practices

1. Use this first when exploring unfamiliar projects
2. Use list_files for specific directories that need deeper inspection
