import Foundation

enum ToolTaxonomy {
    static let readOnly: Set<String> = [
        "read",
        "ls",
        "glob",
        "search",
        "context",
        "web_search",
        "web_fetch"
    ]

    static let mutation: Set<String> = [
        "write",
        "edit",
        "rm"
    ]

    /// Direct file-reading tools (subset of readOnly).
    static let fileReading: Set<String> = ["read"]
}
