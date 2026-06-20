import Foundation

enum LocalModelToolProvider {
    /// Minimal tool set for local models.
    /// Everything except read_file and find is blocked to avoid
    /// overwhelming the small model with too many choices.
    private static let safeToolNames: Set<String> = [
        "read_file",
        "find",
    ]

    static func safeTools(from allTools: [AITool]) -> [AITool] {
        allTools.filter { safeToolNames.contains($0.name) }
    }
}
