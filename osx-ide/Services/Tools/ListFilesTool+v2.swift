import Foundation

/// v2 wrapper for list_files. Delegates to the existing ListFilesTool internally.
/// Note: the existing tool is named "list_dir" — the v2 uses "list_files".
struct ListFilesToolV2: Sendable {
    private let inner: ListFilesTool
    
    init(pathValidator: PathValidator) {
        self.inner = ListFilesTool(pathValidator: pathValidator)
    }

    func definition() -> ToolDefinition {
        ToolDefinition.query(
            name: "list_files",
            desc: "List files and directories in a specified directory. Vendor directories are excluded.",
            params: .object(
                properties: [
                    "path": .string(description: "Directory path to list (absolute or project-relative). Defaults to project root.", enumValues: nil),
                    "recursive": .boolean(desc: "If true, list all files recursively (default: false)"),
                    "max_results": .integer(desc: "Maximum items to return (default 100, max 500)"),
                ],
                required: ["path"]
            ),
            caps: [.directoryList],
            se: .readsFile,
            cf: "items",
            pm: PromptMaterial(
                concise: "List files and directories.",
                standard: "List files and directories in a specified directory. Supports recursive listing.",
                comprehensive: "Lists the contents of a directory. Shows file names, types (file/directory), and relative paths. Use recursive for deep listing. Vendor directories excluded.",
                successCriteria: "Structured list of files and directories with metadata.",
                guidance: nil
            ),
            errorCodes: [
                ErrorCodeDocumentation(code: "FILE_NOT_FOUND", meaning: "Directory not found", recommendedAction: "Use search_project to find it", alternativeTool: "search_project"),
            ],
            exec: { [self] in try await self.run(request: $0) }
        )
    }

    private func run(request: ToolExecutionRequest) async throws -> ToolFeedback {
        let path = try request.requiredString("path")
        let maxResults = request.optionalInt("max_results") ?? 100
        let args: [String: Any] = ["path": path, "max_results": maxResults]
        let result = try await inner.execute(arguments: ToolArguments(args))
        return .success("Listed contents of \(path)", text: result)
    }
}
