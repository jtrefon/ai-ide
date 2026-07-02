import Foundation

/// List files in a directory
struct ListFilesTool: AITool {
    let name = "list_dir"
    let description = "List files and directories under a path. WHAT: Lists files and directories at the given path, with optional filtering. WHEN: Use to explore the project structure before reading or editing files. HOW: path (optional) - directory path, defaults to project root. query (optional, string) - case-insensitive filename filter. limit (optional, int, 1-1000) - max entries to return. OUTPUT: Returns a list of file/directory paths and their types. Vendor/dependency directories show as (excluded)."
    var parameters: [String: Any] {
        FileToolParameterSchemaBuilder.objectSchema(
            properties: [
                "path": FileToolParameterSchemaBuilder.pathProperty(
                    description: "Directory path to list (absolute or project-root-relative). Defaults to project root when omitted."
                ),
                "query": [
                    "type": "string",
                    "description": "Optional case-insensitive filename filter (substring match)."
                ],
                "filter": [
                    "type": "string",
                    "description": "Alias for query."
                ],
                "limit": [
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 1000,
                    "description": "Maximum number of entries to return."
                ]
            ],
            required: []
        )
    }
    let pathValidator: PathValidator

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        let path = (arguments["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = path?.isEmpty == false ? path! : "."
        let query = ((arguments["query"] as? String) ?? (arguments["filter"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let limit = max(1, min(1000, arguments["limit"] as? Int ?? 200))

        let url = try pathValidator.validateAndResolve(resolvedPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return ""
        }
        guard isDirectory.boolValue else {
            return url.lastPathComponent
        }
        var contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        if let query, !query.isEmpty {
            contents = contents.filter { $0.lastPathComponent.lowercased().contains(query) }
        }

        let sortedEntries = contents
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .prefix(limit)
            .map { fileURL -> String in
                let isDirectory = (try? fileURL.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]).isDirectory) ?? false
                let name = isDirectory ? "\(fileURL.lastPathComponent)/" : fileURL.lastPathComponent
                if isDirectory, ToolFileExclusion.isExcluded(url: fileURL) {
                    return "\(name) (excluded)"
                }
                return name
            }

        return sortedEntries.joined(separator: "\n")
    }
}
