import Foundation

struct FindFileTool: AITool {
    let name = "find_file"
    let description = "Find files by name. WHAT: Searches for files matching a given filename query within the project. WHEN: Use when you know the filename but not the full path. Faster than list_files + manual scanning. HOW: query (required, string) - filename to search for (substring match). path (optional) - directory to search in, defaults to project root. OUTPUT: Returns matching file paths."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "The name pattern to search for (e.g., 'train_cli', 'ProfileView'). " +
                        "Partial matches allowed."
                ],
                "path": [
                    "type": "string",
                    "description": "The absolute path to start searching from " +
                        "(defaults to project root if context aware, otherwise required)."
                ]
            ],
            "required": ["pattern", "path"]
        ]
    }

    let pathValidator: PathValidator

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let pattern = arguments["pattern"] as? String else {
            throw AppError.aiServiceError("Missing 'pattern' argument for find_file")
        }
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for find_file")
        }

        let url = try pathValidator.validateAndResolve(path)
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var matches: [String] = []
        let lowerPattern = pattern.lowercased()

        while let fileURL = enumerator?.nextObject() as? URL {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if ToolFileExclusion.isExcluded(url: fileURL) {
                    enumerator?.skipDescendants()
                }
                continue
            }

            let fileName = fileURL.lastPathComponent.lowercased()
            if fileName.contains(lowerPattern) {
                let relativePath = fileURL.relativeTo(url)
                matches.append(relativePath)
            }

            if matches.count >= 50 {
                matches.append("... (truncated)")
                break
            }
        }

        if matches.isEmpty {
            return "No files found matching '\(pattern)'."
        }

        return "Found \(matches.count) file(s):\n" + matches.joined(separator: "\n")
    }
}
