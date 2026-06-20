import Foundation

enum LocalModelToolProvider {
    private static let safeToolNames: Set<String> = [
        "read_file",
        "list_files",
        "get_project_structure",
        "find_file",
        "grep",
        "index_search_text",
        "index_search_symbols",
        "index_find_files",
        "index_list_files",
        "index_read_file",
    ]

    static func safeTools(from allTools: [AITool]) -> [AITool] {
        allTools.filter { safeToolNames.contains($0.name) }
    }
}
