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
    
    public init(fileSystemService: FileSystemService, errorManager: ErrorManagerProtocol, projectRoot: URL) {
        self.fileSystemService = fileSystemService
        self.errorManager = errorManager
        self.projectRoot = projectRoot
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
        var results: [ChatMessage] = []
        
        for toolCall in toolCalls {
            let targetFile: String?
            if toolCall.name == "run_command" {
                targetFile = toolCall.arguments["command"] as? String
            } else {
                targetFile = toolCall.arguments["path"] as? String
            }

            Task {
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
            }
            
            await AIToolTraceLogger.shared.log(type: "tool.execute_start", data: [
                "tool": toolCall.name,
                "toolCallId": toolCall.id,
                "targetPath": targetFile as Any,
                "argumentKeys": Array(toolCall.arguments.keys).sorted()
            ])
            
            // Notify caller about execution start
            let executingMsg = ChatMessage(
                role: .tool,
                content: "Executing \(toolCall.name)...",
                tool: ChatMessageToolContext(
                    toolName: toolCall.name,
                    toolStatus: .executing,
                    targetFile: targetFile,
                    toolCallId: toolCall.id
                )
            )
            onProgress(executingMsg)
            
            let resultMessage: ChatMessage
            if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
                do {
                    var mergedArguments = toolCall.arguments
                    // Inject tool metadata for internal tools (not part of the model schema).
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
                                            targetFile: targetFile,
                                            toolCallId: toolCallId
                                        )
                                    )
                                )
                            }
                        }
                    } else {
                        result = try await tool.execute(arguments: mergedArguments)
                    }

                    Task {
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
                            targetFile: targetFile,
                            toolCallId: toolCall.id
                        )
                    )
                } catch {
                    Task {
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
                    }

                    await AIToolTraceLogger.shared.log(type: "tool.execute_error", data: [
                        "tool": toolCall.name,
                        "toolCallId": toolCall.id,
                        "error": error.localizedDescription
                    ])
                    
                    let errorContent = formatError(error, toolName: toolCall.name)
                    resultMessage = ChatMessage(
                        role: .tool,
                        content: errorContent,
                        tool: ChatMessageToolContext(
                            toolName: toolCall.name,
                            toolStatus: .failed,
                            targetFile: targetFile,
                            toolCallId: toolCall.id
                        )
                    )
                }
            } else {
                Task {
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
                        targetFile: targetFile,
                        toolCallId: toolCall.id
                    )
                )
            }
            
            results.append(resultMessage)
            onProgress(resultMessage)
        }
        
        return results
    }
    
    private func formatError(_ error: Error, toolName: String) -> String {
        if toolName == "index_read_file" {
            let msg = error.localizedDescription
            if msg.lowercased().hasPrefix("file not found") {
                return "Error: \(msg)\n\nHint: do not guess filenames. First use index_find_files(query: \"RegistrationPage\") or index_list_files(query: \"registration-app/src\") to discover the correct path, then call index_read_file with that exact path."
            }
        }
        return "Error: \(error.localizedDescription)"
    }
}
