import Foundation

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

    private static let builtinPairs: [(String, String)] = [
        ("list_directory", "list_files"), ("list_dir", "list_files"),
        ("create_file", "write_file"), ("write", "write_file"), ("write_file_v2", "write_file"),
        ("write_files", "write_file"), ("write_to_file", "write_file"),
        ("edit_file", "replace_in_file"), ("replace_in_file_v2", "replace_in_file"),
        ("apply_patch", "replace_in_file"), ("apply_diff", "patch_file"), ("edit", "patch_file"), ("patch", "patch_file"),
        ("view_file", "read_file"), ("read", "read_file"), ("read_file_v2", "read_file"),
        ("delete", "delete_file"),
        ("search_files", "search_project"), ("grep_search", "search_project"),
        ("find_in_files", "search_project"), ("grep", "grep"),
        ("find_by_name", "find_file"), ("find", "find_file"), ("list_all_files", "list_files"),
        ("web_fetch", "web_browse"), ("fetch_url", "web_browse"), ("http_get", "web_browse"),
        ("browse", "web_browse"),
        ("internet_search", "web_search"), ("google", "web_search"),
        ("search_web", "web_search"), ("web", "web_search"),
        ("run_shell", "run_command"), ("bash", "run_command"), ("terminal", "run_command"),
        ("execute_command", "run_command"), ("run_terminal_command", "run_command"),
        ("run_shell_command", "run_command"), ("cli-mcp-server_run_command", "run_command"),
        ("get_project_structure", "list_files"),
        ("index_find_files", "find_file"), ("index_list_files", "list_files"),
        ("index_read_file", "read_file"), ("index_search_text", "grep"),
    ]

    static let shared: ToolAliasRegistry = {
        let r = ToolAliasRegistry()
        for (alias, canonical) in builtinPairs { r.aliases[alias] = canonical }
        return r
    }()
}
