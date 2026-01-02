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
    
    public var systemPromptAddition: String {
        switch self {
        case .chat:
            return """
            
            **CURRENT MODE: CHAT (Read-Only)**
            You are in Chat mode. You can help users understand their code but CANNOT modify files.
            Available tools: index_find_files, index_list_files, index_search_text, index_read_file, index_search_symbols, run_command (read-only operations only).
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
    public func allowedTools(from allTools: [AITool]) -> [AITool] {
        switch self {
        case .chat:
            // Read-only tools
            return allTools.filter { tool in
                [
                    "index_find_files",
                    "index_list_files",
                    "index_search_text",
                    "index_read_file",
                    "index_search_symbols",
                    "run_command"
                ].contains(tool.name)
            }
        case .agent:
            // All tools
            return allTools
        }
    }
}
