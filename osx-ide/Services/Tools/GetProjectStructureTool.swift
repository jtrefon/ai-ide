import Foundation

struct GetProjectStructureTool: AITool {
    let name = "get_project_structure"
    let description = "Get the file and folder structure of the current project. " +
        "Returns a hierarchical tree view. Vendor/dependency directories " +
        "(node_modules, vendor, .build, Pods, etc.) are collapsed to a single " +
        "line to keep output manageable. Use max_depth for a high-level overview " +
        "(2-3) or omit for the full structure."
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

    private var exclusion: ToolFileExclusion {
        ToolFileExclusion(projectRoot: projectRoot)
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        let maxDepth: Int? = {
            guard let value = arguments["max_depth"] else { return nil }
            if let int = value as? Int { return int }
            if let string = value as? String { return Int(string) }
            return nil
        }()
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

            if exclusion.shouldExclude(item), rendering.isDirectory {
                output += prefix + (isLast ? "└── " : "├── ") + item.lastPathComponent + "/ (excluded)\n"
            } else {
                output += rendering.line
                if rendering.isDirectory {
                    output += buildTree(at: item, prefix: rendering.childPrefix, depth: depth + 1, maxDepth: maxDepth)
                }
            }
        }

        return output
    }

    private func shouldTraverse(depth: Int, maxDepth: Int?) -> Bool {
        guard let maxDepth else { return true }
        return depth < maxDepth
    }

    private func listDirectoryContents(at url: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
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
