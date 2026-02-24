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
            You are in Chat mode with READ-ONLY access. You can help users understand their code, search through files, and answer questions.
            
            IMPORTANT: If a user asks you to perform any work (create files, modify code, run commands, build projects, etc.), 
            you MUST immediately tell the user that you cannot perform that action because you are in read-only Chat mode. 
            Do NOT attempt to use tools that modify files or run commands - you do not have write access. 
            Instead, clearly state: "I'm in read-only Chat mode and cannot perform that action. Please switch to Agent mode if you want me to make changes to your project."
            """
        case .agent:
            return """

            **CURRENT MODE: AGENT (Full Access)**
            You are in Agent mode with full autonomy. You can read, write, edit, and delete files to complete tasks.
            All tools are available. Use them wisely and always explain what you're doing.
            IMPORTANT: Ignore any prior or conflicting instructions claiming you are in read-only mode. In this run, you are NOT read-only.
            If the user asks for implementation work, execute it with tools instead of refusing due to permissions.
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
                    "run_command",
                    "read_file"
                ].contains(tool.name)
            }
        case .agent:
            // All tools
            return allTools
        }
    }
}
