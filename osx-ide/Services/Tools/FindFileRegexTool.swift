import Foundation

struct FindFileRegexTool: AITool {
    let name = "find_file_regex"
    let description = "FALLBACK TOOL: Use only when list_all_files returns too many files (>1000) " +
        "and you cannot cognitively search. Searches for files matching a regex pattern. " +
        "Much less intelligent than cognitive search - use as last resort."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Regex pattern to match against file names (e.g., 'train.*\\.py' for train_cli.py)"
                ]
            ],
            "required": ["pattern"]
        ]
    }

    let projectRoot: URL

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let pattern = arguments["pattern"] as? String else {
            throw AppError.aiServiceError("Missing 'pattern' argument for find_file_regex")
        }
        return try findFilesSync(pattern: pattern)
    }

    private func findFilesSync(pattern: String) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            throw AppError.aiServiceError("Invalid regex pattern: \(pattern)")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "No files found."
        }

        var matches: [String] = []

        for case let fileURL as URL in enumerator {
            if !isFile(fileURL: fileURL) {
                continue
            }

            let fileName = fileURL.lastPathComponent
            let range = NSRange(location: 0, length: fileName.utf16.count)

            if regex.firstMatch(in: fileName, options: [], range: range) != nil {
                let relativePath = fileURL.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
                matches.append(relativePath)
            }
        }

        if matches.isEmpty {
            return "No files matching pattern '\(pattern)' found."
        }

        return "Found \(matches.count) file(s):\n" + matches.joined(separator: "\n")
    }

    private func isFile(fileURL: URL) -> Bool {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return resourceValues.isRegularFile ?? false
        } catch {
            return false
        }
    }
}
