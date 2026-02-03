import Foundation

struct ListAllFilesTool: AITool {
    let name = "list_all_files"
    let description = "Get a flat list of ALL files in the project with their relative paths. " +
        "Use this when you need to find a specific file by name (even partial or misspelled). " +
        "You can cognitively search through this list to identify the correct file."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [:],
            "required": []
        ]
    }

    let projectRoot: URL

    func execute(arguments _: ToolArguments) async throws -> String {
        return getFilesSync()
    }

    private func getFilesSync() -> String {
        let files = getAllFiles(at: projectRoot, relativeTo: projectRoot)

        if files.isEmpty {
            return "No files found in project."
        }

        let fileCount = files.count
        var result = "Project: \(projectRoot.lastPathComponent) (\(fileCount) files)\n\n"
        result += files.joined(separator: "\n")

        return result
    }

    private func getAllFiles(at url: URL, relativeTo root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []

        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory {
                let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                files.append(relativePath)
            }
        }

        return files.sorted()
    }
}
