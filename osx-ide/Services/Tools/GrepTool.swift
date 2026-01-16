import Foundation

struct GrepTool: AITool {
    let name = "grep"
    let description = "Search for a text pattern within files in a directory (recursive)."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "The text pattern to search for."
                ],
                "path": [
                    "type": "string",
                    "description": "The absolute path to the directory to search in."
                ]
            ],
            "required": ["pattern", "path"]
        ]
    }

    let pathValidator: PathValidator

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let pattern = arguments["pattern"] as? String else {
            throw AppError.aiServiceError("Missing 'pattern' argument for grep")
        }
        guard let path = arguments["path"] as? String else {
            throw AppError.aiServiceError("Missing 'path' argument for grep")
        }

        let url = try pathValidator.validateAndResolve(path)
        let results = try await searchInDirectory(url: url, pattern: pattern)

        return results.isEmpty ? "No matches found." : results.joined(separator: "\n")
    }

    private func searchInDirectory(url: URL, pattern: String) async throws -> [String] {
        let fileManager = FileManager.default
        var results: [String] = []

        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if await !isRegularFile(fileURL: fileURL) {
                continue
            }

            let fileResults = await searchInFile(fileURL: fileURL, pattern: pattern)
            results.append(contentsOf: fileResults)

            if results.count > 100 {
                results.append("... too many results, truncated.")
                break
            }
        }

        return results
    }

    private func isRegularFile(fileURL: URL) async -> Bool {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return resourceValues.isRegularFile ?? false
        } catch {
            return false
        }
    }

    private func searchInFile(fileURL: URL, pattern: String) async -> [String] {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            var results: [String] = []

            for (index, line) in lines.enumerated() {
                if line.contains(pattern) {
                    results.append("\(fileURL.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }

            return results
        } catch {
            return []
        }
    }
}
