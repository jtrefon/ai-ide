import Foundation

enum LocalModelToolProvider {
    /// Minimal safe tool set for local models.
    /// Redundant search tools (find_file, grep, index_search_*)
    /// are omitted — use search_project instead, which combines
    /// vector search, symbol lookup, FTS, grep, and filename match.
    private static let safeToolNames: Set<String> = [
        "read_file",
        "list_dir",
        "get_project_structure",
        "search_project",
        "index_list_files",
        "index_read_file",
    ]

    static func safeTools(from allTools: [AITool]) -> [AITool] {
        allTools.filter { safeToolNames.contains($0.name) }
    }
}
