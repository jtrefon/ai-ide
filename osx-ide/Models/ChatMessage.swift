//
//  ChatMessage.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

enum ToolExecutionStatus: String, Codable {
    case executing
    case completed
    case failed
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let codeContext: String?
    let timestamp: Date
    
    // Tool execution properties
    let toolName: String?
    let toolStatus: ToolExecutionStatus?
    let targetFile: String?
    let toolCallId: String? // For Tool Output messages (referencing the call)
    let toolCalls: [AIToolCall]? // For Assistant messages (the calls themselves)
    
    init(role: MessageRole, content: String, codeContext: String? = nil, toolName: String? = nil, toolStatus: ToolExecutionStatus? = nil, targetFile: String? = nil, toolCallId: String? = nil, toolCalls: [AIToolCall]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.codeContext = codeContext
        self.timestamp = Date()
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.targetFile = targetFile
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
    
    // Helper to check if this is a tool execution message
    var isToolExecution: Bool {
        return role == .tool && toolName != nil
    }
}