//
//  AIToolExecutor.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import SwiftUI

/// Handles the execution of AI tools and manages the result reporting.
/// Refactored to use specialized services for better maintainability.
@MainActor
public final class AIToolExecutor {
    final class StringAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String = ""

        func appendAndSnapshot(_ chunk: String) -> (snapshot: String, totalLength: Int) {
            lock.lock()
            defer { lock.unlock() }
            value.append(chunk)
            return (value, value.count)
        }
    }

    // Specialized services
    let logger: ToolExecutionLogger
    let argumentResolver: ToolArgumentResolver
    let messageBuilder: ToolMessageBuilder
    let scheduler: ToolScheduler

    public init(
        fileSystemService: FileSystemService,
        errorManager: any ErrorManagerProtocol,
        projectRoot: URL,
        defaultFilePathProvider: (@MainActor () -> String?)? = nil
    ) {
        // Initialize specialized services
        self.logger = ToolExecutionLogger(errorManager: errorManager)
        self.argumentResolver = ToolArgumentResolver(
            fileSystemService: fileSystemService,
            projectRoot: projectRoot,
            defaultFilePathProvider: defaultFilePathProvider
        )
        self.messageBuilder = ToolMessageBuilder()
        self.scheduler = ToolScheduler()
    }

    // MARK: - Helper Methods (using specialized services)

    func isWriteLikeTool(_ toolName: String) -> Bool {
        return argumentResolver.isWriteLikeTool(toolName)
    }

    func pathKey(for toolCall: AIToolCall) -> String {
        return argumentResolver.pathKey(for: toolCall)
    }

    func resolveTargetFile(for toolCall: AIToolCall) -> String? {
        return argumentResolver.resolveTargetFile(for: toolCall)
    }

    private nonisolated static func isFilePathLikeTool(_ toolName: String) -> Bool {
        switch toolName {
        case "read_file", "write_file", "write_files", "create_file", "delete_file", "replace_in_file":
            return true
        default:
            return false
        }
    }

    private nonisolated static func explicitFilePath(from arguments: [String: Any]) -> String? {
        let candidates: [Any?] = [
            arguments["path"],
            arguments["targetPath"],
            arguments["target_path"],
            arguments["file_path"],
            arguments["file"],
            arguments["target"]
        ]

        return candidates
            .compactMap { $0 as? String }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func resolvedOrInjectedFilePath(arguments: [String: Any], toolName: String) -> String? {
        if let explicit = Self.explicitFilePath(from: arguments) {
            return explicit
        }

        guard Self.isFilePathLikeTool(toolName) else { return nil }
        return nil
    }
}
