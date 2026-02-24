import Foundation

/// Enhanced WriteFilesTool with comprehensive prompt support
extension WriteFilesTool: EnhancedAITool {
    
    var comprehensiveDescription: String {
        return "Write content to multiple files in a single operation. This is the PREFERRED tool for scaffolding projects, creating new file structures, or making coordinated multi-file changes."
    }
    
    var whenToUse: String {
        return """
        - **Project Scaffolding**: Creating new applications with multiple files (React apps, Node.js projects, etc.)
        - **Multi-file Operations**: When you need to create/modify several related files simultaneously
        - **Coordinated Changes**: When files need to be created together to maintain consistency
        - **Initial Setup**: Setting up configuration files, entry points, and component files
        """
    }
    
    var whenNotToUse: String {
        return """
        - **Single File Edits**: Use `replace_in_file` for editing existing files
        - **Small Changes**: Use `write_file` for single file operations
        - **Appending**: This tool overwrites files completely
        - **Incremental Updates**: Use targeted edit tools for small changes
        """
    }
    
    var parameterDescriptions: [String: String] {
        return [
            "files": "Array of file objects with 'path' and 'content' properties. All files are written atomically.",
            "mode": "Write mode - 'overwrite' (default) replaces existing files, 'append' adds content",
            "patch_set_id": "Optional identifier for tracking related changes in a patch set"
        ]
    }
    
    var usageExamples: String {
        return """
        ### Basic Project Scaffolding
        ```json
        {
          "files": [
            {
              "path": "package.json",
              "content": "{\\"name\\": \\"my-app\\", \\"version\\": \\"1.0.0\\"}"
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
        """
    }
    
    var outputStructure: String {
        return """
        ```json
        {
          "status": "completed",
          "message": "Successfully wrote 4 files",
          "payload": {
            "files_written": ["package.json", "index.html", "src/main.jsx", "src/App.jsx"],
            "total_bytes": 1234,
            "execution_time_ms": 45
          },
          "toolName": "write_files",
          "toolCallId": "call_123"
        }
        ```
        """
    }
    
    var successIndicators: String {
        return """
        - All files specified in the `files` array are created/overwritten
        - File content matches exactly what was provided
        - Directory structure is created if needed
        - No permission errors or path conflicts
        - `payload.files_written` contains all expected file paths
        """
    }
    
    var errorHandling: String {
        return """
        - **Permission Denied**: Check file permissions and directory access
        - **Invalid Path**: Verify path syntax and directory existence  
        - **Disk Full**: Check available disk space
        - **Path Conflicts**: Existing files may be overwritten (mode="overwrite")
        - **Partial Failure**: Atomic operation - either all files succeed or none are written
        """
    }
    
    var bestPractices: String {
        return """
        1. **Group Related Files**: Create logically related files together
        2. **Verify Paths**: Ensure all paths are valid and accessible
        3. **Complete Content**: Provide full file content, not partial
        4. **Directory Structure**: Include all necessary directories in paths
        5. **File Extensions**: Use correct extensions for file types
        6. **Atomic Operations**: All files succeed or fail together
        7. **Project Structure**: Follow standard project layout conventions
        """
    }
    
    var integrationNotes: String {
        return """
        - Automatically creates parent directories if they don't exist
        - Overwrites existing files by default (mode="overwrite")
        - Atomic operation - either all files succeed or none are written
        - Preserves file permissions and creates with default permissions
        - Preferred over multiple individual write_file calls for efficiency
        - Integrates with patch set tracking when patch_set_id is provided
        """
    }
}
