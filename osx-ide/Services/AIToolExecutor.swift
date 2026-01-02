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
        onProgress: @escaping (ChatMessage) -> Void
    ) async -> [ChatMessage] {
        var results: [ChatMessage] = []
        
        for toolCall in toolCalls {
            let targetFile = toolCall.arguments["path"] as? String
            
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
                toolName: toolCall.name,
                toolStatus: .executing,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
            onProgress(executingMsg)
            
            let resultMessage: ChatMessage
            if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
                do {
                    let result = try await tool.execute(arguments: toolCall.arguments)
                    
                    await AIToolTraceLogger.shared.log(type: "tool.execute_success", data: [
                        "tool": toolCall.name,
                        "toolCallId": toolCall.id,
                        "resultLength": result.count
                    ])
                    
                    resultMessage = ChatMessage(
                        role: .tool,
                        content: result,
                        toolName: toolCall.name,
                        toolStatus: .completed,
                        targetFile: targetFile,
                        toolCallId: toolCall.id
                    )
                } catch {
                    await AIToolTraceLogger.shared.log(type: "tool.execute_error", data: [
                        "tool": toolCall.name,
                        "toolCallId": toolCall.id,
                        "error": error.localizedDescription
                    ])
                    
                    let errorContent = formatError(error, toolName: toolCall.name)
                    resultMessage = ChatMessage(
                        role: .tool,
                        content: errorContent,
                        toolName: toolCall.name,
                        toolStatus: .failed,
                        targetFile: targetFile,
                        toolCallId: toolCall.id
                    )
                }
            } else {
                await AIToolTraceLogger.shared.log(type: "tool.not_found", data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id
                ])
                
                resultMessage = ChatMessage(
                    role: .tool,
                    content: "Tool not found",
                    toolName: toolCall.name,
                    toolStatus: .failed,
                    targetFile: targetFile,
                    toolCallId: toolCall.id
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
