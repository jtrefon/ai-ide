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
public class AIToolExecutor {
    private actor _AsyncSemaphore: Sendable {
        private var value: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(value: Int) {
            self.value = max(0, value)
        }

        func wait() async {
            if value > 0 {
                value -= 1
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func signal() {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                value += 1
            }
        }
    }

    private actor _AsyncLock: Sendable {
        private var isLocked: Bool = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func lock() async {
            if !isLocked {
                isLocked = true
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            isLocked = true
        }

        func unlock() {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                isLocked = false
            }
        }
    }

    private actor _AsyncLockMap<Key: Hashable & Sendable>: Sendable {
        private var locks: [Key: _AsyncLock] = [:]

        func lock(for key: Key) async {
            let lock = getOrCreateLock(for: key)
            await lock.lock()
        }

        func unlock(for key: Key) async {
            if let lock = locks[key] {
                await lock.unlock()
            }
        }

        private func getOrCreateLock(for key: Key) -> _AsyncLock {
            if let existing = locks[key] {
                return existing
            }
            let newLock = _AsyncLock()
            locks[key] = newLock
            return newLock
        }
    }

    private actor _ToolScheduler: Sendable {
        struct Configuration: Sendable {
            let maxConcurrentReadTasks: Int

            init(maxConcurrentReadTasks: Int = 4) {
                self.maxConcurrentReadTasks = max(1, maxConcurrentReadTasks)
            }
        }

        private let readSemaphore: _AsyncSemaphore
        private let writeLocks = _AsyncLockMap<String>()

        init(configuration: Configuration = Configuration()) {
            self.readSemaphore = _AsyncSemaphore(value: configuration.maxConcurrentReadTasks)
        }

        func runReadTask<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
            await readSemaphore.wait()
            defer { Task { await readSemaphore.signal() } }
            return try await operation()
        }

        func runWriteTask<T: Sendable>(pathKey: String, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
            await writeLocks.lock(for: pathKey)
            defer { Task { await writeLocks.unlock(for: pathKey) } }
            return try await operation()
        }
    }

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
    private let errorManager: ErrorManagerProtocol
    private let projectRoot: URL
    private let scheduler: _ToolScheduler
    
    public init(fileSystemService: FileSystemService, errorManager: ErrorManagerProtocol, projectRoot: URL) {
        self.fileSystemService = fileSystemService
        self.errorManager = errorManager
        self.projectRoot = projectRoot
        self.scheduler = _ToolScheduler()
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
        if let paths = toolCall.arguments["paths"] as? [String], let first = paths.first {
            return first
        }
        return toolCall.name
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
            if toolCall.name == "run_command" {
                targetFile = toolCall.arguments["command"] as? String
            } else {
                targetFile = toolCall.arguments["path"] as? String
            }

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
