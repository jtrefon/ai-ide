import Foundation

enum LocalModelToolProvider {
    /// Tool set for local models tuned for Gemma 4.
    /// Includes read-only exploration, index-based semantic search,
    /// file mutation (with ToolLoopHandler stall detection + recovery),
    /// and shell access.
    private static let safeToolNames: Set<String> = [
        // Core filesystem
        "read_file",
        "list_dir",
        "list_files",
        "write_file",
        "write_files",
        "create_file",
        "replace_in_file",
        "delete_file",
        // Index-backed search & read
        "index_search_text",
        "index_search_symbols",
        "index_find_files",
        "index_list_files",
        "index_read_file",
        "index_list_memories",
        "index_add_memory",
        // Search & structure
        "search_project",
        "find",
        "find_file",
        "find_by_name",
        "grep",
        "grep_search",
        "get_project_structure",
        // Web
        "web_search",
        "web_browse",
        // Terminal
        "run_command",
    ]

    static func safeTools(from allTools: [AITool]) -> [AITool] {
        allTools.filter { safeToolNames.contains($0.name) }
    }
}
