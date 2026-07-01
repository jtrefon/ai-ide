import Foundation

/// v2 wrapper for search_project. Delegates to the existing SearchProjectTool internally.
/// Accepts the dependencies that SearchProjectTool needs (index, projectRoot).
struct SearchProjectToolV2: Sendable {
    private let inner: SearchProjectTool

    init(index: CodebaseIndexProtocol?, projectRoot: URL) {
        self.inner = SearchProjectTool(index: index, projectRoot: projectRoot)
    }

    func definition() -> ToolDefinition {
        ToolDefinition.query(
            name: "search_project",
            desc: "THE PRIMARY search tool for ANY code search task. Finds classes, functions, variables, files, and text patterns using multi-tier search.",
            params: .object(
                properties: [
                    "query": .string(description: "Search term (class name, function name, variable, file name, etc.)", enumValues: nil),
                    "max_results": .integer(desc: "Maximum results (default 50, max 200)"),
                ],
                required: ["query"]
            ),
            caps: [.fileSearch, .indexSearch, .indexSemantic],
            se: .readsFile,
            cf: "items",
            pm: PromptMaterial(
                concise: "Search the project for code, symbols, and files.",
                standard: "Multi-tier search: file name, FTS5, symbols, vector. Use this FIRST for any code discovery.",
                comprehensive: "Searches via file name trie, FTS5 index, symbol table, vector similarity, and grep fallback. ALWAYS use this first before grep or find_file.",
                successCriteria: "Results include file path, line number, match type, and context snippet.",
                guidance: ToolGuidance(
                    whenToUse: "Always use this first for code search instead of grep or find_file.",
                    whenNotToUse: nil,
                    bestPractices: [
                        "Always use this first before grep or find_file",
                        "Be specific: class names and exact file names give the best results",
                        "Check spelling: if no results, check for typos",
                    ]
                )
            ),
            errorCodes: [
                ErrorCodeDocumentation(code: "INDEX_NOT_AVAILABLE", meaning: "Index is still building", recommendedAction: "Wait and retry, or use grep", alternativeTool: nil),
            ],
            exec: { [self] in try await self.run(request: $0) }
        )
    }

    private func run(request: ToolExecutionRequest) async throws -> ToolFeedback {
        let query = try request.requiredString("query")
        let maxResults = request.optionalInt("max_results") ?? 50
        let args: [String: Any] = ["query": query, "max_results": maxResults]
        let result = try await inner.execute(arguments: ToolArguments(args))
        if result.isEmpty {
            return .success("No results found for '\(query)'")
        }
        return .success("Search results for '\(query)'", text: result)
    }
}
