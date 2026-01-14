//
//  ToolExecutionLogger.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation

/// Handles logging of tool execution events for debugging and monitoring.
@MainActor
final class ToolExecutionLogger {
    private let errorManager: any ErrorManagerProtocol

    init(errorManager: any ErrorManagerProtocol) {
        self.errorManager = errorManager
    }

    /// Logs the start of tool execution
    func logToolExecuteStart(
        conversationId: String?,
        toolCall: AIToolCall,
        targetFile: String?
    ) async {
        let context = "Tool execution started"
        let details = """
        Tool: \(toolCall.name)
        Target File: \(targetFile ?? "None")
        Arguments: \(toolCall.arguments)
        """

        await errorManager.handle(
            AppError.aiServiceError(context),
            context: "Tool Execution Start"
        )
    }

    /// Logs progress during tool execution
    func logToolExecuteProgress(
        conversationId: String?,
        toolCall: AIToolCall,
        progress: String
    ) async {
        let context = "Tool execution progress"
        let details = """
        Tool: \(toolCall.name)
        Progress: \(progress)
        """

        await errorManager.handle(
            AppError.aiServiceError(context),
            context: "Tool Execution Progress"
        )
    }

    /// Logs successful tool execution
    func logToolExecuteSuccess(
        conversationId: String?,
        toolCall: AIToolCall,
        resultLength: Int
    ) async {
        let context = "Tool execution completed successfully"
        let details = """
        Tool: \(toolCall.name)
        Result Length: \(resultLength) characters
        """

        await errorManager.handle(
            AppError.aiServiceError(context),
            context: "Tool Execution Success"
        )
    }

    /// Logs tool execution errors
    func logToolExecuteError(
        conversationId: String?,
        toolCall: AIToolCall,
        error: Error
    ) async {
        let context = "Tool execution failed"
        let details = """
        Tool: \(toolCall.name)
        Error: \(error.localizedDescription)
        Arguments: \(toolCall.arguments)
        """

        await errorManager.handle(
            error,
            context: "Tool Execution Error"
        )
    }

    /// Logs when a tool is not found
    func logToolNotFound(
        conversationId: String?,
        toolCall: AIToolCall
    ) async {
        let context = "Requested tool not found"
        let details = """
        Requested Tool: \(toolCall.name)
        Available Tools: [Tool names would be listed here]
        """

        await errorManager.handle(
            AppError.aiServiceError(context),
            context: "Tool Not Found"
        )
    }
}
