import Foundation

/// Adapter that provides line-range based file patching (patch_file)
/// as an AITool for the v1 ToolLoopHandler pipeline.
/// Implements the proven patch logic directly — no v2 dependencies.
struct PatchFileToolAdapter: AITool {
    let projectRoot: URL

    let name = "edit"
    let description = "Edit an existing file by line range. Preferred for all edits — surgical, precise, context-efficient. Read the file first for line numbers."

    var parameters: [String: Any] {
        ["type": "object", "properties": [
            "path": ["type": "string", "description": "Absolute or project-relative path to the file to patch."],
            "start_line": ["type": "integer", "description": "1-based line where replacement begins."],
            "end_line": ["type": "integer", "description": "1-based inclusive end line."],
            "new_content": ["type": "string", "description": "Replacement content for the line range."],
        ], "required": ["path", "start_line", "end_line", "new_content"]]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        let path = raw["path"] as? String ?? ""
        let startLine = (raw["start_line"] as? Int) ?? 0
        let endLine = (raw["end_line"] as? Int) ?? 0
        let newContent = raw["new_content"] as? String ?? ""

        let url: URL
        if path.hasPrefix("/") { url = URL(fileURLWithPath: path) }
        else { url = projectRoot.appendingPathComponent(path) }

        let fm = FileManager.default
        guard let data = fm.contents(atPath: url.path) else {
            return "status: error\nmessage: File not found: \(path)\nerror_code: FILE_NOT_FOUND\nrecoverable: true"
        }
        guard var content = String(data: data, encoding: .utf8) else {
            return "status: error\nmessage: Binary file\n error_code: BINARY_FILE\nrecoverable: false"
        }

        var lines = content.components(separatedBy: "\n")
        let total = lines.count
        guard startLine >= 1, startLine <= total, endLine >= startLine, endLine <= total else {
            return "status: error\nmessage: Invalid range \(startLine)-\(endLine), file has \(total) lines\nerror_code: INVALID_LINE_RANGE\nrecoverable: true"
        }

        let oldContent = lines[(startLine - 1)...(endLine - 1)].joined(separator: "\n")
        lines.replaceSubrange((startLine - 1)...(endLine - 1), with: [newContent])
        let newFull = lines.joined(separator: "\n")

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try Data(newFull.utf8).write(to: tmp, options: .atomic)
        try fm.replaceItemAt(url, withItemAt: tmp)

        guard let vData = fm.contents(atPath: url.path),
              let vContent = String(data: vData, encoding: .utf8),
              vContent == newFull else {
            return "status: error\nmessage: Verification failed\nerror_code: VERIFICATION_FAILED\nrecoverable: true"
        }

        var diff = "--- a (lines \(startLine)-\(endLine))\n+++ b (lines \(startLine)-\(endLine))\n"
        for l in oldContent.components(separatedBy: "\n") { diff += "-\(l)\n" }
        for l in newContent.components(separatedBy: "\n") { diff += "+\(l)\n" }

        return "status: success\nmessage: Patched \(path) (lines \(startLine)-\(endLine))\ncontent:\n  \(diff.replacingOccurrences(of: "\n", with: "\n  "))"
    }
}
