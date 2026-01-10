//
//  AIToolExecutor.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import SwiftUI

/// Handles the execution of AI tools and manages the result reporting.
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

    private let fileSystemService: FileSystemService
    private let errorManager: any ErrorManagerProtocol
    private let projectRoot: URL
    private let scheduler: ToolScheduler
    private let defaultFilePathProvider: (@MainActor () -> String?)?
    
    public init(
        fileSystemService: FileSystemService,
        errorManager: any ErrorManagerProtocol,
        projectRoot: URL,
        defaultFilePathProvider: (@MainActor () -> String?)? = nil
    ) {
        self.fileSystemService = fileSystemService
        self.errorManager = errorManager
        self.projectRoot = projectRoot
        self.scheduler = ToolScheduler()
        self.defaultFilePathProvider = defaultFilePathProvider
    }

    private func isWriteLikeTool(_ toolName: String) -> Bool {
        switch toolName {
        case "write_file", "write_files", "create_file", "delete_file", "replace_in_file":
            return true
        case "run_command":
            return true
        default:
            return false
        }
    }

    private func pathKey(for toolCall: AIToolCall) -> String {
        if toolCall.name == "run_command" {
            return "run_command"
        }
        if let path = toolCall.arguments["path"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path
        }
        if let path = toolCall.arguments["targetPath"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path
        }
        if let paths = toolCall.arguments["paths"] as? [String], let first = paths.first {
            return first
        }
        return toolCall.name
    }

    private func resolveTargetFile(for toolCall: AIToolCall) -> String? {
        if toolCall.name == "run_command" {
            return toolCall.arguments["command"] as? String
        }

        let candidates: [Any?] = [
            toolCall.arguments["path"],
            toolCall.arguments["targetPath"],
            toolCall.arguments["target_path"],
            toolCall.arguments["file_path"],
            toolCall.arguments["file"],
            toolCall.arguments["target"],
        ]
        return candidates
            .compactMap { $0 as? String }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
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

        let tasks: [Task<ChatMessage, Never>] = toolCalls.map { toolCall in
            let targetFile: String?
            targetFile = resolveTargetFile(for: toolCall)

            let executingMsg = ChatMessage(
                role: .tool,
                content: "Executing \(toolCall.name)...",
                tool: ChatMessageToolContext(
                    toolName: toolCall.name,
                    toolStatus: .executing,
                    target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCall.id)
                )
            )
            onProgress(executingMsg)

            return Task { [weak self] in
                guard let self else {
                    return ChatMessage(role: .tool, content: "Tool executor unavailable")
                }

                let pathKey = self.pathKey(for: toolCall)

                let run: @Sendable () async -> ChatMessage = {
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

                    let resultMessage: ChatMessage
                    if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
                        do {
                            var mergedArguments = toolCall.arguments
                            mergedArguments["_tool_call_id"] = toolCall.id
                            if let conversationId {
                                mergedArguments["_conversation_id"] = conversationId
                            }

                            let explicitPath = Self.explicitFilePath(from: mergedArguments)
                            let fallbackPath: String? = {
                                guard explicitPath == nil else { return nil }
                                guard Self.isFilePathLikeTool(toolCall.name) else { return nil }
                                guard self.defaultFilePathProvider != nil else { return nil }
                                return "__needs_main_actor__"
                            }()

                            let injectedPath: String?
                            if fallbackPath == "__needs_main_actor__" {
                                injectedPath = await MainActor.run {
                                    self.defaultFilePathProvider?()?.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } else {
                                injectedPath = explicitPath
                            }

                            if let injectedPath, !injectedPath.isEmpty, mergedArguments["path"] == nil {
                                mergedArguments["path"] = injectedPath
                            }

                            let result: String
                            if let streamingTool = tool as? any AIToolProgressReporting {
                                let toolCallId = toolCall.id
                                let accumulator = StringAccumulator()
                                result = try await streamingTool.execute(arguments: mergedArguments) { chunk in
                                    let (snapshot, totalLength) = accumulator.appendAndSnapshot(chunk)

                                    let cappedChunk = String(chunk.suffix(16_384))
                                    Task {
                                        await ExecutionLogStore.shared.append(
                                            ExecutionLogAppendRequest(
                                                toolCallId: toolCallId,
                                                type: "tool.execute_progress",
                                                data: [
                                                    "chunk": cappedChunk,
                                                    "chunkLength": chunk.count,
                                                    "totalLength": totalLength
                                                ],
                                                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
                                            )
                                        )
                                    }

                                    Task { @MainActor in
                                        onProgress(
                                            ChatMessage(
                                                role: .tool,
                                                content: snapshot,
                                                tool: ChatMessageToolContext(
                                                    toolName: toolCall.name,
                                                    toolStatus: .executing,
                                                    target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCallId)
                                                )
                                            )
                                        )
                                    }
                                }
                            } else {
                                result = try await tool.execute(arguments: mergedArguments)
                            }

                            await AppLogger.shared.info(category: .tool, message: "tool.execute_success", metadata: [
                                "conversationId": conversationId as Any,
                                "tool": toolCall.name,
                                "toolCallId": toolCall.id,
                                "resultLength": result.count
                            ])

                            await ExecutionLogStore.shared.append(
                                ExecutionLogAppendRequest(
                                    toolCallId: toolCall.id,
                                    type: "tool.execute_success",
                                    data: [
                                        "resultLength": result.count
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
                                        "resultLength": result.count
                                    ]
                                )
                            }

                            await AIToolTraceLogger.shared.log(type: "tool.execute_success", data: [
                                "tool": toolCall.name,
                                "toolCallId": toolCall.id,
                                "resultLength": result.count
                            ])

                            resultMessage = ChatMessage(
                                role: .tool,
                                content: result,
                                tool: ChatMessageToolContext(
                                    toolName: toolCall.name,
                                    toolStatus: .completed,
                                    target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCall.id)
                                )
                            )
                        } catch {
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

                            let errorContent = Self.formatError(error, toolName: toolCall.name)
                            resultMessage = ChatMessage(
                                role: .tool,
                                content: errorContent,
                                tool: ChatMessageToolContext(
                                    toolName: toolCall.name,
                                    toolStatus: .failed,
                                    target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCall.id)
                                )
                            )
                        }
                    } else {
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

                        resultMessage = ChatMessage(
                            role: .tool,
                            content: "Tool not found",
                            tool: ChatMessageToolContext(
                                toolName: toolCall.name,
                                toolStatus: .failed,
                                target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCall.id)
                            )
                        )
                    }

                    Task { @MainActor in
                        onProgress(resultMessage)
                    }

                    return resultMessage
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
                    return ChatMessage(role: .tool, content: "Error: \(error.localizedDescription)")
                }
            }
        }

        for task in tasks {
            let message = await task.value
            results.append(message)
        }

        return results
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
