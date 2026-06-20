//
//  ToolLoopMessageBuilder.swift
//  osx-ide
//
//  Message building logic for focused tool execution
//

import Foundation

/// Builds focused messages for tool execution to maximize context window usage
@MainActor
struct ToolLoopMessageBuilder {
    
    /// Build focused execution messages for tool loop continuation
    static func buildFocusedExecutionMessages(
        userInput: String,
        conversationId: String,
        projectRoot: URL
    ) async -> [ChatMessage] {
        var messages: [ChatMessage] = []
        
        // Add system instruction
        let systemMessage = ChatMessage(
            role: .system,
            content: """
            You are in tool execution mode. Focus on completing the user's request efficiently.
            
            Rules:
            1. Use tools to make concrete progress on the task
            2. Avoid asking clarifying questions - make reasonable assumptions
            3. If a tool fails, try alternative approaches
            4. Complete the task systematically but efficiently
            5. Provide brief status updates only when necessary
            """
        )
        messages.append(systemMessage)
        
        // Add plan from ConversationPlanStore if available
        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        if let plan = await ConversationPlanStore.shared.get(conversationId: conversationId),
           !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let planMessage = ChatMessage(
                role: .system,
                content: """
                Current Implementation Plan:
                \(plan)
                
                Focus on completing the remaining unchecked items.
                """
            )
            messages.append(planMessage)
        }
        
        // Add user request
        let userMessage = ChatMessage(
            role: .user,
            content: userInput
        )
        messages.append(userMessage)
        
        return messages
    }
    
    /// Build continuation message when model drops out without tool calls
    static func buildContinuationMessage(
        userInput: String,
        conversationId: String,
        projectRoot: URL,
        lastResponse: String?
    ) async -> [ChatMessage] {
        var messages = await buildFocusedExecutionMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot
        )
        
        // Add context about why we're continuing
        let continuationContext = ChatMessage(
            role: .system,
            content: """
            The previous response didn't include tool calls needed to complete the task. 
            Please continue with tool execution to make progress on: \(userInput)
            
            \(lastResponse.map { "Previous response: \($0)" } ?? "")
            """
        )
        messages.insert(continuationContext, at: 1) // After system message, before plan
        
        return messages
    }
    
    /// Build error recovery message when tool execution fails
    static func buildErrorRecoveryMessage(
        userInput: String,
        conversationId: String,
        projectRoot: URL,
        error: String,
        failedToolCall: AIToolCall
    ) async -> [ChatMessage] {
        var messages = await buildFocusedExecutionMessages(
            userInput: userInput,
            conversationId: conversationId,
            projectRoot: projectRoot
        )
        
        // Add error context
        let errorContext = ChatMessage(
            role: .system,
            content: """
            Tool execution failed:
            - Tool: \(failedToolCall.name)
            - Arguments: \(failedToolCall.arguments)
            - Error: \(error)
            
            Please try alternative approaches to complete the task: \(userInput)
            """
        )
        messages.insert(errorContext, at: 1) // After system message, before plan
        
        return messages
    }
    
    /// Build completion message when task is finished
    static func buildCompletionMessage(
        userInput: String,
        completedActions: [String]
    ) -> ChatMessage {
        let actionsSummary = completedActions.isEmpty ? 
            "Task completed successfully." : 
            "Completed actions:\n" + completedActions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        
        return ChatMessage(
            role: .assistant,
            content: """
            \(actionsSummary)
            
            The task "\(userInput)" has been completed.
            """
        )
    }
}
