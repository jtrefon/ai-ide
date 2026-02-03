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
    private let projectRoot: URL
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
        var mergedArguments = toolCall.arguments

        // Inject file path if needed
        if Self.isFilePathLikeTool(toolCall.name) {
            let explicitPath = Self.explicitFilePath(from: toolCall.arguments)
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
        return arguments["path"] as? String
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
}
