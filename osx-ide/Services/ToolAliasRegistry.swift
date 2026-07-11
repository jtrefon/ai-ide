import Foundation

/// Maps legacy tool names to their current canonical names for backward
/// compatibility during the v3 toolset migration.
///
/// PHASE 2+ — Remove after sufficient model training data has updated.
/// Models calling old names (`read_file`, `write_file`, etc.) will instead
/// get a "tool not found" error which teaches them the new names.
final class ToolAliasRegistry: @unchecked Sendable {
    private var aliases: [String: String] = [:]
    private let lock = NSLock()

    func register(alias: String, canonical: String) {
        lock.withLock { aliases[alias] = canonical }
    }

    func canonicalName(for name: String) -> String {
        lock.withLock {
            let lowercased = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return aliases[lowercased] ?? lowercased
        }
    }

    func hasAlias(_ name: String) -> Bool {
        lock.withLock { aliases[name.lowercased()] != nil }
    }

    /// Old → new name mappings for the v3 toolset migration.
    private static let builtinPairs: [(String, String)] = [
        // Read
        ("read_file", "read"), ("view_file", "read"), ("read_file_v2", "read"), ("index_read_file", "read"),
        // Write / Edit
        ("write_file", "write"), ("write_files", "write"), ("create_file", "write"), ("write_to_file", "write"), ("write_file_v2", "write"),
        ("patch_file", "edit"), ("replace_in_file", "edit"), ("edit_file", "edit"), ("replace_in_file_v2", "edit"), ("apply_patch", "edit"), ("apply_diff", "edit"), ("patch", "edit"), ("edit", "edit"),
        // Delete
        ("delete_file", "rm"), ("delete", "rm"),
        // Search
        ("search_project", "search"), ("grep", "search"), ("grep_search", "search"), ("search_files", "search"), ("find_in_files", "search"),
        ("index_search_text", "search"), ("index_search_symbols", "search"),
        // File discovery
        ("find_file", "glob"), ("find_by_name", "glob"), ("find", "glob"), ("index_find_files", "glob"),
        // List
        ("list_files", "ls"), ("list_dir", "ls"), ("list_directory", "ls"), ("list_all_files", "ls"), ("index_list_files", "ls"), ("get_project_structure", "ls"),
        // Execution
        ("run_command", "bash"), ("run_shell", "bash"), ("bash", "bash"), ("terminal", "bash"), ("execute_command", "bash"), ("run_terminal_command", "bash"), ("run_shell_command", "bash"), ("cli-mcp-server_run_command", "bash"),
        // Web
        ("web_search", "web_search"), ("internet_search", "web_search"), ("google", "web_search"), ("search_web", "web_search"), ("web", "web_search"),
        ("web_browse", "web_fetch"), ("web_fetch", "web_fetch"), ("fetch_url", "web_fetch"), ("http_get", "web_fetch"), ("browse", "web_fetch"),
    ]

    static let shared: ToolAliasRegistry = {
        let r = ToolAliasRegistry()
        for (alias, canonical) in builtinPairs { r.aliases[alias] = canonical }
        return r
    }()
}
