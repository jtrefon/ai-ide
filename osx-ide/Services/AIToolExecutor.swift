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
    private final class StringAccumulator: @unchecked Sendable {
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
    private let logger: ToolExecutionLogger
    private let argumentResolver: ToolArgumentResolver
    private let messageBuilder: ToolMessageBuilder
    private let scheduler: ToolScheduler
    
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
    
    private func isWriteLikeTool(_ toolName: String) -> Bool {
        return argumentResolver.isWriteLikeTool(toolName)
    }

    private func pathKey(for toolCall: AIToolCall) -> String {
        return argumentResolver.pathKey(for: toolCall)
    }

    private func resolveTargetFile(for toolCall: AIToolCall) -> String? {
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
            arguments["target"],
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

    private nonisolated static func makeToolExecutionMessage(
        content: String,
        toolName: String,
        status: ToolExecutionStatus,
        targetFile: String?,
        toolCallId: String
    ) -> ChatMessage {
        ChatMessage(
            role: .tool,
            content: content,
            tool: ChatMessageToolContext(
                toolName: toolName,
                toolStatus: status,
                target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCallId)
            )
        )
    }

    private func logToolExecuteStart(
        conversationId: String?,
        toolCall: AIToolCall,
        targetFile: String?
    ) async {
        await AppLogger.shared.info(category: .tool, message: "tool.execute_start", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "targetPath": targetFile as Any
        ])

        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCall.id,
                type: "tool.execute_start",
                data: [
                    "targetPath": targetFile as Any
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
            )
        )

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.execute_start",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id,
                    "targetPath": targetFile as Any
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.execute_start", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "targetPath": targetFile as Any,
            "argumentKeys": Array(toolCall.arguments.keys).sorted()
        ])
    }

    private func logToolExecuteProgress(
        conversationId: String?,
        toolName: String,
        toolCallId: String,
        chunk: String,
        totalLength: Int
    ) async {
        let cappedChunk = String(chunk.suffix(16_384))
        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCallId,
                type: "tool.execute_progress",
                data: [
                    "chunk": cappedChunk,
                    "chunkLength": chunk.count,
                    "totalLength": totalLength
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolName)
            )
        )
    }

    private func logToolExecuteSuccess(conversationId: String?, toolCall: AIToolCall, resultLength: Int) async {
        await AppLogger.shared.info(category: .tool, message: "tool.execute_success", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "resultLength": resultLength
        ])

        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCall.id,
                type: "tool.execute_success",
                data: [
                    "resultLength": resultLength
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
            )
        )

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.execute_success",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id,
                    "resultLength": resultLength
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.execute_success", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "resultLength": resultLength
        ])
    }

    private func logToolExecuteError(conversationId: String?, toolCall: AIToolCall, error: Error) async {
        await AppLogger.shared.error(category: .tool, message: "tool.execute_error", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "error": error.localizedDescription
        ])

        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCall.id,
                type: "tool.execute_error",
                data: [
                    "error": error.localizedDescription
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
            )
        )

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.execute_error",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id,
                    "error": error.localizedDescription
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.execute_error", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "error": error.localizedDescription
        ])
    }

    private func logToolNotFound(conversationId: String?, toolCall: AIToolCall) async {
        await AppLogger.shared.error(category: .tool, message: "tool.not_found", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id
        ])

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.not_found",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.not_found", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id
        ])
    }

    private func buildMergedArguments(toolCall: AIToolCall, conversationId: String?) async -> [String: Any] {
        var mergedArguments = toolCall.arguments
        mergedArguments["_tool_call_id"] = toolCall.id
        if let conversationId {
            mergedArguments["_conversation_id"] = conversationId
        }

        // Use the argument resolver to handle file path injection
        let resolvedArguments = await argumentResolver.buildMergedArguments(
            toolCall: toolCall,
            conversationId: conversationId
        )
        
        // Merge the resolved arguments
        for (key, value) in resolvedArguments {
            mergedArguments[key] = value
        }

        return mergedArguments
    }

    private nonisolated static func sendToolProgressSnapshot(
        snapshot: String,
        toolName: String,
        toolCallId: String,
        targetFile: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) {
        Task { @MainActor in
            onProgress(
                Self.makeToolExecutionMessage(
                    content: snapshot,
                    toolName: toolName,
                    status: .executing,
                    targetFile: targetFile,
                    toolCallId: toolCallId
                )
            )
        }
    }

    private func executeToolAndCaptureResult(
        tool: AITool,
        toolCall: AIToolCall,
        mergedArguments: [String: Any],
        conversationId: String?,
        targetFile: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) async throws -> String {
        if let streamingTool = tool as? any AIToolProgressReporting {
            let toolCallId = toolCall.id
            let accumulator = StringAccumulator()
            return try await streamingTool.execute(arguments: ToolArguments(mergedArguments)) { chunk in
                let (snapshot, totalLength) = accumulator.appendAndSnapshot(chunk)

                Task {
                    await self.logToolExecuteProgress(
                        conversationId: conversationId,
                        toolName: toolCall.name,
                        toolCallId: toolCallId,
                        chunk: chunk,
                        totalLength: totalLength
                    )
                }

                Self.sendToolProgressSnapshot(
                    snapshot: snapshot,
                    toolName: toolCall.name,
                    toolCallId: toolCallId,
                    targetFile: targetFile,
                    onProgress: onProgress
                )
            }
        }

        return try await tool.execute(arguments: ToolArguments(mergedArguments))
    }

    private func makeToolCallFinalMessage(result: Result<String, Error>, toolCall: AIToolCall, targetFile: String?) -> ChatMessage {
        switch result {
        case .success(let content):
            return Self.makeToolExecutionMessage(
                content: content,
                toolName: toolCall.name,
                status: .completed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        case .failure(let error):
            let errorContent = Self.formatError(error, toolName: toolCall.name)
            return Self.makeToolExecutionMessage(
                content: errorContent,
                toolName: toolCall.name,
                status: .failed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        }
    }

    private func executeToolCall(
        toolCall: AIToolCall,
        availableTools: [AITool],
        conversationId: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void,
        targetFile: String?
    ) async -> ChatMessage {
        await logToolExecuteStart(conversationId: conversationId, toolCall: toolCall, targetFile: targetFile)

        let resultMessage: ChatMessage
        if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
            let result: Result<String, Error>
            do {
                let mergedArguments = await buildMergedArguments(toolCall: toolCall, conversationId: conversationId)
                let content = try await executeToolAndCaptureResult(
                    tool: tool,
                    toolCall: toolCall,
                    mergedArguments: mergedArguments,
                    conversationId: conversationId,
                    targetFile: targetFile,
                    onProgress: onProgress
                )
                await logToolExecuteSuccess(conversationId: conversationId, toolCall: toolCall, resultLength: content.count)
                result = .success(content)
            } catch {
                await logToolExecuteError(conversationId: conversationId, toolCall: toolCall, error: error)
                result = .failure(error)
            }

            resultMessage = makeToolCallFinalMessage(result: result, toolCall: toolCall, targetFile: targetFile)
        } else {
            await logToolNotFound(conversationId: conversationId, toolCall: toolCall)
            resultMessage = Self.makeToolExecutionMessage(
                content: "Tool not found",
                toolName: toolCall.name,
                status: .failed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        }

        Task { @MainActor in
            onProgress(resultMessage)
        }

        return resultMessage
    }
    
    /// Executes a list of tool calls and returns the results as ChatMessages.
    /// - Parameters:
    ///   - toolCalls: The tool calls to execute.
    ///   - availableTools: The list of available tools.
    ///   - onProgress: Callback for reporting progress of individual tool execution.
    /// - Returns: An array of tool result messages.
    public func executeBatch(
        _ toolCalls: [AIToolCall],
        availableTools: [AITool],
        conversationId: String? = nil,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) async -> [ChatMessage] {
        if toolCalls.isEmpty { return [] }

        var results: [ChatMessage] = []
        results.reserveCapacity(toolCalls.count)

        let tasks: [Task<ChatMessage, Never>] = toolCalls.map {
            makeExecuteBatchTask(
                toolCall: $0,
                availableTools: availableTools,
                conversationId: conversationId,
                onProgress: onProgress
            )
        }

        for task in tasks {
            let message = await task.value
            results.append(message)
        }

        return results
    }

    private func makeExecuteBatchTask(
        toolCall: AIToolCall,
        availableTools: [AITool],
        conversationId: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) -> Task<ChatMessage, Never> {
        let targetFile: String?
        targetFile = resolveTargetFile(for: toolCall)

        let executingMsg = Self.makeToolExecutionMessage(
            content: "Executing \(toolCall.name)...",
            toolName: toolCall.name,
            status: .executing,
            targetFile: targetFile,
            toolCallId: toolCall.id
        )
        onProgress(executingMsg)

        return Task { [weak self] in
            guard let self else {
                return Self.makeToolExecutionMessage(
                    content: "Tool executor unavailable",
                    toolName: toolCall.name,
                    status: .failed,
                    targetFile: targetFile,
                    toolCallId: toolCall.id
                )
            }

            let pathKey = self.pathKey(for: toolCall)

            let run: @Sendable () async -> ChatMessage = {
                await self.executeToolCall(
                    toolCall: toolCall,
                    availableTools: availableTools,
                    conversationId: conversationId,
                    onProgress: onProgress,
                    targetFile: targetFile
                )
            }

            do {
                if self.isWriteLikeTool(toolCall.name) {
                    return try await self.scheduler.runWriteTask(pathKey: pathKey) {
                        await run()
                    }
                }
                return try await self.scheduler.runReadTask {
                    await run()
                }
            } catch {
                return Self.makeToolExecutionMessage(
                    content: "Error: \(error.localizedDescription)",
                    toolName: toolCall.name,
                    status: .failed,
                    targetFile: targetFile,
                    toolCallId: toolCall.id
                )
            }
        }
    }
    
    private nonisolated static func formatError(_ error: Error, toolName: String) -> String {
        if toolName == "index_read_file" {
            let msg = error.localizedDescription
            if msg.lowercased().hasPrefix("file not found") {
                return "Error: \(msg)\n\nHint: do not guess filenames. First use index_find_files(query: \"RegistrationPage\") or index_list_files(query: \"registration-app/src\") to discover the correct path, then call index_read_file with that exact path."
            }
        }
        return "Error: \(error.localizedDescription)"
    }
}
