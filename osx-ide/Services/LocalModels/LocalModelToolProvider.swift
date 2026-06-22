import Foundation

enum LocalModelToolProvider {
    /// Minimally sufficient tool set for local models.
    /// Read-only: find (search), read_file, list_dir, get_project_structure.
    /// Removed: grep, find_file, index_* tools — find subsumes those.
    private static let safeToolNames: Set<String> = [
        "read_file",
        "find",
        "list_dir",
        "get_project_structure",
    ]

    static func safeTools(from allTools: [AITool]) -> [AITool] {
        allTools.filter { safeToolNames.contains($0.name) }
    }
}
