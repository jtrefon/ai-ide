//
//  ChatMessage.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}

public enum ToolExecutionStatus: String, Codable, Sendable {
    case executing
    case completed
    case failed
}

public struct ChatMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let reasoning: String?
    public let codeContext: String?
    public let timestamp: Date

    // Tool execution properties
    public let toolName: String?
    public var toolStatus: ToolExecutionStatus?
    public var targetFile: String?
    public var toolCallId: String? // For Tool Output messages (referencing the call)
    public let toolCalls: [AIToolCall]? // For Assistant messages (the calls themselves)

    public init(
        role: MessageRole,
        content: String,
        context: ChatMessageContentContext = ChatMessageContentContext(),
        tool: ChatMessageToolContext = ChatMessageToolContext()
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.reasoning = context.reasoning
        self.codeContext = context.codeContext
        self.timestamp = Date()
        self.toolName = tool.toolName
        self.toolStatus = tool.toolStatus
        self.targetFile = tool.targetFile
        self.toolCallId = tool.toolCallId
        self.toolCalls = tool.toolCalls.isEmpty ? nil : tool.toolCalls
    }

    public init(
        id: UUID,
        role: MessageRole,
        content: String,
        timestamp: Date,
        context: ChatMessageContentContext = ChatMessageContentContext(),
        tool: ChatMessageToolContext = ChatMessageToolContext()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = context.reasoning
        self.codeContext = context.codeContext
        self.timestamp = timestamp
        self.toolName = tool.toolName
        self.toolStatus = tool.toolStatus
        self.targetFile = tool.targetFile
        self.toolCallId = tool.toolCallId
        self.toolCalls = tool.toolCalls.isEmpty ? nil : tool.toolCalls
    }

    // Helper to check if this is a tool execution message
    public var isToolExecution: Bool {
        return role == .tool && toolName != nil
    }
}
