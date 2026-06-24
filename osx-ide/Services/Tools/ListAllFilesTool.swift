import Foundation

struct ListAllFilesTool: AITool {
    let name = "list_all_files"
    let description = "Get a flat list of ALL files in the project with their relative paths. " +
        "Use this when you need to find a specific file by name (even partial or misspelled). " +
        "You can cognitively search through this list to identify the correct file. " +
        "Skips vendor/dependency directories automatically."
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
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "No files found in project."
        }

        var files: [String] = []

        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if ToolFileExclusion.isExcluded(url: fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let relativePath = fileURL.relativeTo(projectRoot)
            files.append(relativePath)
        }

        if files.isEmpty {
            return "No files found in project."
        }

        files.sort()

        let fileCount = files.count
        var result = "Project: \(projectRoot.lastPathComponent) (\(fileCount) files)\n\n"
        result += files.joined(separator: "\n")

        return result
    }
}
