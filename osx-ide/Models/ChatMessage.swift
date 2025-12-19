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
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let codeContext: String?
    let timestamp: Date
    
    init(role: MessageRole, content: String, codeContext: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.codeContext = codeContext
        self.timestamp = Date()
    }
}