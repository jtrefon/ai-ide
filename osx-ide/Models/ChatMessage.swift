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
    
    public init(role: MessageRole, content: String, reasoning: String? = nil, codeContext: String? = nil, toolName: String? = nil, toolStatus: ToolExecutionStatus? = nil, targetFile: String? = nil, toolCallId: String? = nil, toolCalls: [AIToolCall]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.codeContext = codeContext
        self.timestamp = Date()
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.targetFile = targetFile
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
    
    // Helper to check if this is a tool execution message
    public var isToolExecution: Bool {
        return role == .tool && toolName != nil
    }
}