import Foundation

struct GetProjectStructureTool: AITool {
    let name = "get_project_structure"
    let description = "Get the complete file and folder structure of the current project. " +
        "Returns a hierarchical tree view of all files and directories. " +
        "Use this to understand the project layout and cognitively identify files even with partial or misspelled names."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "max_depth": [
                    "type": "integer",
                    "description": "Maximum depth to traverse (default: unlimited). " +
                        "Use 2-3 for overview, unlimited for complete structure."
                ]
            ],
            "required": []
        ]
    }

    let projectRoot: URL

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let maxDepth = arguments["max_depth"] as? Int else {
            throw AppError.aiServiceError("Missing 'max_depth' argument for get_project_structure")
        }
        return buildTreeSync(maxDepth: maxDepth)
    }

    private func buildTreeSync(maxDepth: Int?) -> String {
        var result = "Project Structure: \(projectRoot.lastPathComponent)/\n"
        result += buildTree(at: projectRoot, prefix: "", depth: 0, maxDepth: maxDepth)
        return result
    }

    private func buildTree(at url: URL, prefix: String, depth: Int, maxDepth: Int?) -> String {
        guard shouldTraverse(depth: depth, maxDepth: maxDepth) else { return "" }
        guard let contents = listDirectoryContents(at: url) else { return "" }

        var output = ""
        for (index, item) in contents.enumerated() {
            let isLast = index == contents.count - 1
            let rendering = renderTreeNode(prefix: prefix, isLast: isLast, item: item)
            output += rendering.line
            if rendering.isDirectory {
                output += buildTree(at: item, prefix: rendering.childPrefix, depth: depth + 1, maxDepth: maxDepth)
            }
        }

        return output
    }

    private func shouldTraverse(depth: Int, maxDepth: Int?) -> Bool {
        guard let maxDepth else { return true }
        return depth < maxDepth
    }

    private func listDirectoryContents(at url: URL) -> [URL]? {
        return try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
    }

    private func renderTreeNode(prefix: String, isLast: Bool, item: URL) -> (line: String, childPrefix: String, isDirectory: Bool) {
        let connector = isLast ? "└── " : "├── "
        let childPrefix = prefix + (isLast ? "    " : "│   ")
        let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let displayName = isDirectory ? item.lastPathComponent + "/" : item.lastPathComponent
        return (line: prefix + connector + displayName + "\n", childPrefix: childPrefix, isDirectory: isDirectory)
    }
}
