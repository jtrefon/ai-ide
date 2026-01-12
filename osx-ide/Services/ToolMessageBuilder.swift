//
//  ToolMessageBuilder.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation

/// Builds ChatMessage objects for tool execution status and results.
final class ToolMessageBuilder {
    
    /// Creates a tool execution message with specified status and content
    static func makeToolExecutionMessage(
        content: String,
        toolName: String,
        status: ToolExecutionStatus,
        targetFile: String?,
        toolCallId: String
    ) -> ChatMessage {
        return ChatMessage(
            role: .tool,
            content: content,
            tool: ChatMessageToolContext(
                toolName: toolName,
                toolStatus: status,
                target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCallId)
            )
        )
    }
    
    /// Creates the final message for a tool call based on execution result
    func makeToolCallFinalMessage(
        result: Result<String, Error>,
        toolCall: AIToolCall,
        targetFile: String?
    ) -> ChatMessage {
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
            return Self.makeToolExecutionMessage(
                content: "Error: \(Self.formatError(error, toolName: toolCall.name))",
                toolName: toolCall.name,
                status: .failed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        }
    }
    
    /// Formats error messages with tool-specific context
    private static func formatError(_ error: Error, toolName: String) -> String {
        if toolName == "index_read_file" {
            let msg = error.localizedDescription
            if msg.lowercased().hasPrefix("file not found") {
                return """
                \(msg)
                
                Hint: do not guess filenames. First use index_find_files(query: "RegistrationPage") or index_list_files(query: "registration-app/src") to discover the correct path, then call index_read_file with that exact path.
                """
            }
        }
        return error.localizedDescription
    }
    
    /// Creates a progress snapshot message for streaming tool output
    static func makeToolProgressSnapshot(
        content: String,
        toolName: String,
        toolCallId: String,
        targetFile: String?
    ) -> ChatMessage {
        return makeToolExecutionMessage(
            content: content,
            toolName: toolName,
            status: .executing,
            targetFile: targetFile,
            toolCallId: toolCallId
        )
    }
}
