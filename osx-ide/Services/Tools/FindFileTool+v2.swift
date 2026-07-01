import Foundation

/// v2 wrapper for find_file. Delegates to the existing FindFileTool internally.
struct FindFileToolV2: Sendable {
    private let inner: FindFileTool
    
    init(pathValidator: PathValidator) {
        self.inner = FindFileTool(pathValidator: pathValidator)
    }

    func definition() -> ToolDefinition {
        ToolDefinition.query(
            name: "find_file",
            desc: "Find files by name (case insensitive). Secondary tool — use search_project for non-file-name searches.",
            params: .object(
                properties: [
                    "name": .string(description: "File name or pattern to search for (e.g., 'ProfileView', '*.swift')", enumValues: nil),
                    "max_results": .integer(desc: "Maximum results (default 20, max 100)"),
                ],
                required: ["name"]
            ),
            caps: [.fileSearch],
            se: .readsFile,
            cf: "items",
            pm: PromptMaterial(
                concise: "Find a file by name.",
                standard: "Search for files by name or partial name match across the project.",
                comprehensive: "Searches the project for files matching the given name or pattern. Skips vendor directories automatically.",
                successCriteria: "List of matching file paths.",
                guidance: nil
            ),
            exec: { [self] in try await self.run(request: $0) }
        )
    }

    private func run(request: ToolExecutionRequest) async throws -> ToolFeedback {
        let name = try request.requiredString("name")
        let maxResults = request.optionalInt("max_results") ?? 20
        let args: [String: Any] = ["pattern": name, "max_results": maxResults]
        let result = try await inner.execute(arguments: ToolArguments(args))
        if result.isEmpty {
            return .success("No files found matching '\(name)'")
        }
        return .success("Files matching '\(name)'", text: result)
    }
}
