import Foundation

enum LocalModelToolProvider {
    /// Tool set for local models.
    /// Read-only file ops + search + shell access so the agent can
    /// explore, read, and run CLI commands when needed.
    private static let safeToolNames: Set<String> = [
        "read_file",
        "find",
        "list_dir",
        "get_project_structure",
        "run_command",
        "web_search",
    ]

    static func safeTools(from allTools: [AITool]) -> [AITool] {
        allTools.filter { safeToolNames.contains($0.name) }
    }
}
