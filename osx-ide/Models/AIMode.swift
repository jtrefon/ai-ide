//
//  AIMode.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

public enum AIMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat = "Chat"
    case agent = "Agent"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .chat:
            return "Read-only mode. AI can view files and search but cannot modify anything."
        case .agent:
            return "Full autonomy. AI can read, write, edit, and delete files to complete tasks."
        }
    }

    public var icon: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .agent:
            return "gearshape.2"
        }
    }

    // Determine which tools are available in this mode
    public func allowedTools(from allTools: [AITool]) -> [AITool] {
        switch self {
        case .chat:
            // Chat mode - NO tools (read-only interface)
            return []
        case .agent:
            // Agent mode - ALL tools
            return allTools
        }
    }
}
