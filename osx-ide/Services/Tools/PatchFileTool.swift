import Foundation

/// PatchFileTool — Line-range based file patching with content verification.
/// Replaces replace_in_file (exact text match) with a more reliable approach.
/// Design: line-range + verification, beats all competitors.
struct PatchFileTool: @unchecked Sendable {
    let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func definition() -> ToolDefinition {
        ToolDefinition.command(name: "patch_file",
            desc: "Apply a targeted edit by line range. Use INSTEAD of replace_in_file.",
            params: .object(properties: [
                "path": .string(description: "Absolute or project-relative path", enumValues: nil),
                "start_line": .integer(desc: "1-based line where replacement begins"),
                "end_line": .integer(desc: "1-based line where replacement ends (inclusive). Set = start_line for single-line edits."),
                "new_content": .string(description: "Replacement content for the specified line range", enumValues: nil),
            ], required: ["path", "start_line", "end_line", "new_content"]),
            caps: [.fileWrite], se: [.writesFile, .readsFile],
            pm: PromptMaterial(concise: "Apply a targeted edit by line range.", standard: "Replace lines start_line-end_line with new_content. More reliable than replace_in_file (no exact text match needed).", comprehensive: "Patches a file by replacing a line range with new content. Reads file, extracts old content at those lines, replaces, writes atomically, then VERIFIES by reading back. Returns structured diff. Use INSTEAD of replace_in_file for all targeted edits.", successCriteria: "File patched, verified, returns old/new diff.", guidance: ToolGuidance(whenToUse: "Always use instead of replace_in_file for targeted edits.", whenNotToUse: "New files or complete rewrites — use write_file.", bestPractices: ["Prefer patch_file over replace_in_file", "Read the file first to get correct line numbers", "start_line/end_line are 1-based inclusive", "For single-line edits, start_line = end_line"])),
            errorCodes: [
                ErrorCodeDocumentation(code: "FILE_NOT_FOUND", meaning: "File does not exist", recommendedAction: "Check path", alternativeTool: nil),
                ErrorCodeDocumentation(code: "INVALID_LINE_RANGE", meaning: "start_line/end_line out of bounds", recommendedAction: "Read file to see line count", alternativeTool: "read_file"),
                ErrorCodeDocumentation(code: "VERIFICATION_FAILED", meaning: "Written content doesn't match expected", recommendedAction: "Re-read file", alternativeTool: "read_file"),
            ],
            exec: { [self] in try await self.exec(request: $0) }
        )
    }

    // Internal so PatchFileToolAdapter can call it. Not public — use definition() for external access.
    internal func exec(request: ToolExecutionRequest) async throws -> ToolFeedback {
        let path = try request.requiredString("path")
        let startLine = try (request.optionalInt("start_line") ?? { throw ToolExecError.missing("start_line") }())
        let endLine = try (request.optionalInt("end_line") ?? { throw ToolExecError.missing("end_line") }())
        let newContent = try request.requiredString("new_content")
        let url = URL(fileURLWithPath: path)

        // Read file
        guard let data = fileManager.contents(atPath: url.path) else {
            return err("File not found: \(path)", code: "FILE_NOT_FOUND")
        }
        guard var content = String(data: data, encoding: .utf8) else {
            return err("File is not valid UTF-8", code: "BINARY_FILE")
        }

        var lines = content.components(separatedBy: "\n")
        let total = lines.count
        guard startLine >= 1, startLine <= total, endLine >= startLine, endLine <= total else {
            return err("Invalid range \(startLine)-\(endLine), file has \(total) lines", code: "INVALID_LINE_RANGE")
        }

        let oldContent = lines[(startLine - 1)...(endLine - 1)].joined(separator: "\n")
        lines.replaceSubrange((startLine - 1)...(endLine - 1), with: [newContent])
        let newFull = lines.joined(separator: "\n")

        // Write atomically
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try Data(newFull.utf8).write(to: tmp, options: .atomic)
        try fileManager.replaceItemAt(url, withItemAt: tmp)

        // Verify
        guard let vData = fileManager.contents(atPath: url.path),
              let vContent = String(data: vData, encoding: .utf8),
              vContent == newFull else {
            return err("Verification failed — content mismatch", code: "VERIFICATION_FAILED")
        }

        // Build diff
        let oldLines = oldContent.components(separatedBy: "\n")
        let newLines = newContent.components(separatedBy: "\n")
        var diff = "--- a (lines \(startLine)-\(startLine + oldLines.count - 1))\n"
        diff += "+++ b (lines \(startLine)-\(startLine + newLines.count - 1))\n"
        for l in oldLines { diff += "-\(l)\n" }
        for l in newLines { diff += "+\(l)\n" }

        return ToolFeedback.success("Patched \(path) (lines \(startLine)-\(endLine))",
            text: diff,
            meta: ["path": path, "startLine": "\(startLine)", "endLine": "\(endLine)", "verified": "true"])
    }

    private func err(_ msg: String, code: String) -> ToolFeedback {
        ToolFeedback(status: .error, message: msg, content: nil,
                     error: ToolErrorInfo(code: code, message: msg, recoverable: true))
    }
}
