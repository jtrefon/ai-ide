//
//  ToolArgumentResolver.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation

/// Handles resolution and merging of tool arguments, including file path injection.
@MainActor
final class ToolArgumentResolver {
    private let fileSystemService: FileSystemService
    private var projectRoot: URL
    private let defaultFilePathProvider: (@MainActor () -> String?)?

    init(
        fileSystemService: FileSystemService,
        projectRoot: URL,
        defaultFilePathProvider: (@MainActor () -> String?)? = nil
    ) {
        self.fileSystemService = fileSystemService
        self.projectRoot = projectRoot
        self.defaultFilePathProvider = defaultFilePathProvider
    }

    func updateProjectRoot(_ newRoot: URL) {
        projectRoot = newRoot
    }

    /// Resolves the target file for a tool call
    func resolveTargetFile(for toolCall: AIToolCall) -> String? {
        return resolvedOrInjectedFilePath(
            arguments: toolCall.arguments,
            toolName: toolCall.name
        )
    }

    /// Builds merged arguments for tool execution
    func buildMergedArguments(
        toolCall: AIToolCall,
        conversationId: String?
    ) async -> [String: Any] {
        var mergedArguments = Self.normalizeArguments(
            toolCall.arguments,
            toolName: toolCall.name
        )

        // Inject file path if needed
        if Self.isFilePathLikeTool(toolCall.name) {
            let explicitPath = Self.explicitFilePath(from: mergedArguments)
            if let injectedPath = await resolveInjectedPath(
                toolName: toolCall.name,
                explicitPath: explicitPath
            ) {
                mergedArguments["path"] = injectedPath
            }
        }

        return mergedArguments
    }

    /// Determines if a file path should be injected for the tool
    private func resolvedOrInjectedFilePath(
        arguments: [String: Any],
        toolName: String
    ) -> String? {
        if Self.isFilePathLikeTool(toolName) {
            let explicitPath = Self.explicitFilePath(from: arguments)
            return explicitPath ?? defaultFilePathProvider?()
        }
        return nil
    }

    /// Checks if a tool requires file path injection
    private static func isFilePathLikeTool(_ toolName: String) -> Bool {
        switch toolName {
        case "read_file", "write_file", "write_files", "create_file",
             "delete_file", "replace_in_file", "index_read_file":
            return true
        default:
            return false
        }
    }

    /// Extracts explicit file path from tool arguments
    private static func explicitFilePath(from arguments: [String: Any]) -> String? {
        if let path = arguments["path"] as? String,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path
        }
        let aliases = ["targetPath", "target_path", "file_path", "filepath", "file", "target"]
        for alias in aliases {
            if let path = arguments[alias] as? String,
               !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return path
            }
        }
        return nil
    }

    /// Resolves injected path for file-based tools
    private func resolveInjectedPath(
        toolName: String,
        explicitPath: String?
    ) async -> String? {
        if let explicitPath = explicitPath {
            return explicitPath
        }

        // Use default file path provider if available
        return defaultFilePathProvider?()
    }

    /// Generates a unique path key for tool scheduling
    func pathKey(for toolCall: AIToolCall) -> String {
        if let targetFile = resolveTargetFile(for: toolCall) {
            return targetFile
        }
        return toolCall.name
    }

    /// Checks if a tool performs write operations
    func isWriteLikeTool(_ toolName: String) -> Bool {
        switch toolName {
        case "write_file", "write_files", "create_file", "delete_file", "replace_in_file":
            return true
        case "run_command":
            return true
        default:
            return false
        }
    }

    // MARK: - Argument normalization

    private static func normalizeArguments(
        _ arguments: [String: Any],
        toolName: String
    ) -> [String: Any] {
        var normalized = arguments
        let rawChunk = normalized["_raw_args_chunk"] as? String
        let hasRawChunkOnlyPayload = rawChunk != nil && normalized.keys.allSatisfy {
            $0 == "_raw_args_chunk" || $0 == "_tool_call_id" || $0 == "_conversation_id"
        }

        if let rawChunk,
           let parsed = parseJSONObject(from: rawChunk) {
            mergeMissingKeys(from: parsed, into: &normalized)
        }

        normalizeCommonPathAliases(in: &normalized)

        switch toolName {
        case "write_file", "create_file":
            if let rawChunk {
                fillMissingFieldsFromRawChunk(rawChunk, toolName: toolName, into: &normalized)
            }
            if hasRawChunkOnlyPayload && !hasCompleteWriteArguments(normalized) {
                return normalized
            }
            if (normalized["path"] as? String)?.isEmpty != false {
                copyFirstString(from: ["path", "file", "target", "target_path", "file_path"], to: "path", in: &normalized)
            }
            if (normalized["content"] as? String)?.isEmpty != false {
                copyFirstString(
                    from: ["new_text", "text", "body", "data", "contents", "code", "file_content"],
                    to: "content",
                    in: &normalized
                )
            }
            if let files = normalized["files"] as? [[String: Any]],
               let first = files.first {
                if (normalized["path"] as? String)?.isEmpty != false,
                   let path = first["path"] as? String,
                   !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    normalized["path"] = path
                }
                if (normalized["content"] as? String)?.isEmpty != false,
                   let content = first["content"] as? String,
                   !content.isEmpty {
                    normalized["content"] = content
                }
            }
        case "replace_in_file":
            if let rawChunk {
                fillMissingFieldsFromRawChunk(rawChunk, toolName: toolName, into: &normalized)
            }
            if hasRawChunkOnlyPayload && !hasCompleteReplaceArguments(normalized) {
                return normalized
            }
            copyFirstString(from: ["oldText", "find", "search", "old"], to: "old_text", in: &normalized)
            copyFirstString(from: ["newText", "replacement", "replace", "to", "content"], to: "new_text", in: &normalized)
        case "write_files":
            normalizeWriteFilesArguments(in: &normalized)
            if hasRawChunkOnlyPayload && !hasCompleteWriteFilesArguments(normalized) {
                return normalized
            }
            normalizeWriteFilesArguments(in: &normalized)
        default:
            break
        }

        if let rawChunk {
            if hasRawChunkOnlyPayload && isWriteMutationTool(toolName) {
                return normalized
            }
            fillMissingFieldsFromRawChunk(rawChunk, toolName: toolName, into: &normalized)
        }

        return normalized
    }

    private static func isWriteMutationTool(_ toolName: String) -> Bool {
        switch toolName {
        case "write_file", "write_files", "create_file", "replace_in_file":
            return true
        default:
            return false
        }
    }

    private static func hasCompleteWriteArguments(_ arguments: [String: Any]) -> Bool {
        guard let path = arguments["path"] as? String,
              let content = arguments["content"] as? String else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !content.isEmpty
    }

    private static func hasCompleteReplaceArguments(_ arguments: [String: Any]) -> Bool {
        guard let path = arguments["path"] as? String,
              let oldText = arguments["old_text"] as? String,
              let newText = arguments["new_text"] as? String else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !oldText.isEmpty && !newText.isEmpty
    }

    private static func hasCompleteWriteFilesArguments(_ arguments: [String: Any]) -> Bool {
        guard let files = arguments["files"] as? [[String: Any]], !files.isEmpty else { return false }
        return files.allSatisfy { entry in
            guard let path = entry["path"] as? String,
                  let content = entry["content"] as? String else { return false }
            return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !content.isEmpty
        }
    }

    private static func normalizeCommonPathAliases(in arguments: inout [String: Any]) {
        if (arguments["path"] as? String)?.isEmpty == false {
            return
        }
        copyFirstString(
            from: ["targetPath", "target_path", "file_path", "filepath", "file", "target"],
            to: "path",
            in: &arguments
        )
    }

    private static func normalizeWriteFilesArguments(in arguments: inout [String: Any]) {
        let sharedContent = (arguments["content"] as? String)
            ?? (arguments["new_text"] as? String)
            ?? (arguments["text"] as? String)

        if let rawFilesString = arguments["files"] as? String {
            if let parsedObject = parseJSONObject(from: rawFilesString),
               let nestedFiles = parsedObject["files"] as? [Any] {
                arguments["files"] = nestedFiles
            } else if let parsedArray = parseJSONArray(from: rawFilesString) {
                arguments["files"] = parsedArray
            }
        }

        if let genericFiles = arguments["files"] as? [Any] {
            let normalizedFiles = genericFiles.compactMap { value -> [String: Any]? in
                if let dict = value as? [String: Any] {
                    var entry = dict
                    normalizeCommonPathAliases(in: &entry)
                    if (entry["content"] as? String)?.isEmpty != false, let sharedContent {
                        entry["content"] = sharedContent
                    }
                    if let path = entry["path"] as? String,
                       let content = entry["content"] as? String,
                       !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return ["path": path, "content": content]
                    }
                }
                return nil
            }
            if !normalizedFiles.isEmpty {
                arguments["files"] = normalizedFiles
                return
            }
        }

        if let path = arguments["path"] as? String,
           let content = sharedContent ?? (arguments["content"] as? String),
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments["files"] = [["path": path, "content": content]]
            return
        }

        if let rawChunk = arguments["_raw_args_chunk"] as? String {
            if let parsedObject = parseJSONObject(from: rawChunk),
               let nestedFiles = parsedObject["files"] as? [Any] {
                arguments["files"] = nestedFiles
                arguments.removeValue(forKey: "_raw_args_chunk")
                normalizeWriteFilesArguments(in: &arguments)
                return
            }

            if let parsedArray = parseJSONArray(from: rawChunk) {
                arguments["files"] = parsedArray
                arguments.removeValue(forKey: "_raw_args_chunk")
                normalizeWriteFilesArguments(in: &arguments)
                return
            }
        }
    }

    private static func fillMissingFieldsFromRawChunk(
        _ rawChunk: String,
        toolName: String,
        into arguments: inout [String: Any]
    ) {
        switch toolName {
        case "write_file", "create_file":
            if (arguments["path"] as? String)?.isEmpty != false,
               let path = extractStringValue(from: rawChunk, keys: ["path", "file", "target", "target_path", "file_path"]) {
                arguments["path"] = path
            }
            if (arguments["content"] as? String)?.isEmpty != false,
               let content = extractStringValue(from: rawChunk, keys: ["content", "new_text", "text", "body", "data", "contents", "code"]) {
                arguments["content"] = content
            }
        case "replace_in_file":
            if (arguments["old_text"] as? String)?.isEmpty != false,
               let old = extractStringValue(from: rawChunk, keys: ["old_text", "oldText", "find", "search", "old"]) {
                arguments["old_text"] = old
            }
            if (arguments["new_text"] as? String)?.isEmpty != false,
               let newText = extractStringValue(from: rawChunk, keys: ["new_text", "newText", "replacement", "replace", "to", "content"]) {
                arguments["new_text"] = newText
            }
        default:
            break
        }
    }

    private static func extractStringValue(from raw: String, keys: [String]) -> String? {
        if let decodedRaw = decodeJSONStringFragment(raw), decodedRaw != raw {
            if let decodedValue = extractStringValue(from: decodedRaw, keys: keys) {
                return decodedValue
            }
        }

        for key in keys {
            let pattern = #""\#(key)"\s*:\s*"((?:\\.|[^"\\])*)""#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            guard let match = regex.firstMatch(in: raw, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: raw) else {
                continue
            }
            let escaped = String(raw[valueRange])
            let decoded = decodeJSONStringFragment(escaped) ?? escaped
            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return decoded
            }
        }
        return nil
    }

    private static func decodeJSONStringFragment(_ raw: String) -> String? {
        let wrapped = "\"\(raw)\""
        guard let data = wrapped.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return nil
        }
        return decoded
    }

    private static func copyFirstString(
        from keys: [String],
        to destination: String,
        in arguments: inout [String: Any]
    ) {
        if let existing = arguments[destination] as? String,
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        for key in keys {
            if let value = arguments[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                arguments[destination] = value
                return
            }
        }
    }

    private static func mergeMissingKeys(from source: [String: Any], into destination: inout [String: Any]) {
        for (key, value) in source {
            if destination[key] == nil {
                destination[key] = value
            }
        }
    }

    private static func parseJSONObject(from raw: String) -> [String: Any]? {
        func parse(_ candidate: String) -> [String: Any]? {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else {
                return nil
            }
            return dict
        }

        if let direct = parse(raw) {
            return direct
        }

        if let decodedRaw = decodeJSONStringFragment(raw), decodedRaw != raw {
            if let decoded = parse(decodedRaw) {
                return decoded
            }
        }

        if let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}"),
           start < end {
            let bounded = String(raw[start...end])
            if let parsed = parse(bounded) {
                return parsed
            }
            if let decodedBounded = decodeJSONStringFragment(bounded), decodedBounded != bounded,
               let parsed = parse(decodedBounded) {
                return parsed
            }
        }

        let wrapped = "{\(raw)}"
        if let parsed = parse(wrapped) {
            return parsed
        }

        if let decodedWrapped = decodeJSONStringFragment(wrapped), decodedWrapped != wrapped {
            return parse(decodedWrapped)
        }

        return nil
    }

    private static func parseJSONArray(from raw: String) -> [Any]? {
        func parse(_ candidate: String) -> [Any]? {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let array = object as? [Any] else {
                return nil
            }
            return array
        }

        if let direct = parse(raw) {
            return direct
        }

        if let decodedRaw = decodeJSONStringFragment(raw), decodedRaw != raw {
            if let decoded = parse(decodedRaw) {
                return decoded
            }
        }

        if let start = raw.firstIndex(of: "["),
           let end = raw.lastIndex(of: "]"),
           start < end {
            let bounded = String(raw[start...end])
            if let parsed = parse(bounded) {
                return parsed
            }
            if let decodedBounded = decodeJSONStringFragment(bounded), decodedBounded != bounded {
                return parse(decodedBounded)
            }
        }

        return nil
    }
}
