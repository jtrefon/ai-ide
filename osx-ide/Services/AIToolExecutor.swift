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
}
