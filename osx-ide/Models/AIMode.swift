//
//  AIMode.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

enum AIMode: String, Codable, CaseIterable, Identifiable {
    case chat = "Chat"
    case agent = "Agent"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .chat:
            return "Read-only mode. AI can view files and search but cannot modify anything."
        case .agent:
            return "Full autonomy. AI can read, write, edit, and delete files to complete tasks."
        }
    }
    
    var icon: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .agent:
            return "gearshape.2"
        }
    }
    
    var systemPromptAddition: String {
        switch self {
        case .chat:
            return """
            
            **CURRENT MODE: CHAT (Read-Only)**
            You are in Chat mode. You can help users understand their code but CANNOT modify files.
            Available tools: read_file, list_files, grep, run_command (read-only operations only).
            If the user asks you to make changes, politely explain that you're in Chat mode and suggest they switch to Agent mode.
            """
        case .agent:
            return """
            
            **CURRENT MODE: AGENT (Full Access)**
            You are in Agent mode with full autonomy. You can read, write, edit, and delete files to complete tasks.
            All tools are available. Use them wisely and always explain what you're doing.
            """
        }
    }
    
    // Determine which tools are available in this mode
    func allowedTools(from allTools: [AITool]) -> [AITool] {
        switch self {
        case .chat:
            // Read-only tools
            return allTools.filter { tool in
                ["read_file", "list_files", "grep", "run_command"].contains(tool.name)
            }
        case .agent:
            // All tools
            return allTools
        }
    }
}
