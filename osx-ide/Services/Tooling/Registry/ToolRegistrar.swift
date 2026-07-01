import Foundation

/// Registers all Phase 1 tools into the ToolRegistry.
/// Each tool provides its own ToolDefinition via a definition() method.
enum ToolRegistrar {
    /// Register all tools with optional external dependencies.
    /// - Parameters:
    ///   - r: The registry to register into
    ///   - pathValidator: Optional path validator for file tools (required for production)
    ///   - index: Optional codebase index for search tools (required for production)
    ///   - projectRoot: Project root URL (required for search tools)
    static func registerAll(
        in r: ToolRegistryProtocol,
        pathValidator: PathValidator? = nil,
        index: CodebaseIndexProtocol? = nil,
        projectRoot: URL? = nil
    ) {
        // Tier 1 — Fully implemented wrappers
        r.register(ReadFileToolV2().definition())
        r.register(WriteFileToolV2().definition())
        r.register(PatchFileTool().definition())

        if let pv = pathValidator {
            r.register(ListFilesToolV2(pathValidator: pv).definition())
            r.register(FindFileToolV2(pathValidator: pv).definition())
        } else {
            // Register placeholder definitions that throw
            r.register(ToolDefinition.query(name: "list_files", desc: "List files.", params: .object(properties: [:], required: []), caps: [.directoryList], cf: "items",
                pm: PromptMaterial(concise: "List files.", standard: "List files.", comprehensive: "List files.", successCriteria: nil, guidance: nil),
                exec: { _ in throw ToolExecError.missing("pathValidator required") }))
            r.register(ToolDefinition.query(name: "find_file", desc: "Find file.", params: .object(properties: [:], required: []), caps: [.fileSearch], cf: "items",
                pm: PromptMaterial(concise: "Find file.", standard: "Find file.", comprehensive: "Find file.", successCriteria: nil, guidance: nil),
                exec: { _ in throw ToolExecError.missing("pathValidator required") }))
        }

        if let idx = index, let root = projectRoot {
            r.register(SearchProjectToolV2(index: idx, projectRoot: root).definition())
        } else {
            r.register(ToolDefinition.query(name: "search_project", desc: "Search project.", params: .object(properties: [:], required: []), caps: [.fileSearch, .indexSearch], cf: "items",
                pm: PromptMaterial(concise: "Search.", standard: "Search.", comprehensive: "Search.", successCriteria: nil, guidance: nil),
                exec: { _ in throw ToolExecError.missing("index and projectRoot required") }))
        }

        // Tier 2 — Placeholders for remaining tools
        for (name, desc, caps, cf) in placeholderTools {
            r.register(ToolDefinition.query(
                name: name, desc: desc,
                params: .object(properties: [:], required: []),
                caps: caps, cf: cf,
                pm: PromptMaterial(concise: desc, standard: desc, comprehensive: desc, successCriteria: nil, guidance: nil),
                exec: { _ in throw ToolExecError.missing("not yet implemented") }
            ))
        }
    }

    private static let placeholderTools: [(String, String, Set<ToolCapability>, String)] = [
        ("get_project_structure", "Show project directory tree.", [.projectStructure], "text"),
        ("index_search_text", "Search indexed file contents.", [.indexSearch], "items"),
        ("index_search_symbols", "Search symbols by name.", [.indexSearch], "items"),
        ("index_find_files", "Find files by path pattern.", [.indexSearch], "items"),
        ("index_list_files", "List indexed files.", [.indexSearch], "items"),
        ("index_read_file", "Read file via index cache.", [.indexSearch], "text"),
        ("index_list_memories", "List agent memories.", [.indexMemory], "items"),
        ("index_add_memory", "Add agent memory.", [.indexMemory], "text"),
        ("web_search", "Search the web using Google.", [.webSearch], "items"),
        ("web_browse", "Read full web pages with a browser.", [.webBrowse], "text"),
    ]
}
