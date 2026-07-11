import Foundation

enum LocalModelToolProvider {
    /// Tool set for local models tuned for Gemma 4.
    /// Includes read-only exploration, index-based semantic search,
    /// file mutation (with ToolLoopHandler stall detection + recovery),
    /// and shell access.
    private static let safeToolNames: Set<String> = [
        // Core filesystem
        "read",
        "ls",
        "write",
        "edit",
        "rm",
        // Search & index
        "search",
        "glob",
        "context",
        // Web
        "web_search",
        "web_fetch",
        // Terminal
        "bash",
        // Planning
        "plan",
        // Pinned rules
        "pinned_rule_add",
        "pinned_rule_remove",
        "pinned_rule_list",
    ]

    static func safeTools(from allTools: [AITool]) -> [AITool] {
        allTools.filter { safeToolNames.contains($0.name) }
    }
}
