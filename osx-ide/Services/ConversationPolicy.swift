import Foundation

protocol ConversationPolicyProtocol {
    func allowedTools(
        for stage: AIRequestStage?,
        mode: AIMode,
        from availableTools: [AITool]
    ) -> [AITool]
}

final class ConversationPolicy: ConversationPolicyProtocol {
    func allowedTools(
        for stage: AIRequestStage?,
        mode: AIMode,
        from availableTools: [AITool]
    ) -> [AITool] {
        // First filter by mode
        let modeAllowedTools = mode.allowedTools(from: availableTools)
        
        // Then filter by stage if in agent mode
        guard mode == .agent, let stage = stage else {
            return modeAllowedTools
        }
        
        // Agent mode with stage-based filtering
        switch stage {
        case .strategic_planning, .tactical_planning, .qa_tool_output_review, .qa_quality_review:
            // Read-only tools for planning and QA stages
            let readOnlyToolNames: Set<String> = [
                "index_find_files",
                "index_list_files", 
                "index_search_text",
                "index_read_file",
                "index_search_symbols",
                "read_file",
                "list_files",
                "conversation_fold"
            ]
            return modeAllowedTools.filter { readOnlyToolNames.contains($0.name) }
            
        case .initial_response:
            // No tools for initial response to save context
            return []
            
        case .tool_loop, .delivery_gate, .final_response:
            // All tools for execution stages
            return modeAllowedTools
            
        case .warmup, .other:
            // Default to read-only for unknown stages
            let readOnlyToolNames: Set<String> = [
                "index_find_files",
                "index_list_files",
                "index_search_text", 
                "index_read_file",
                "index_search_symbols",
                "read_file",
                "list_files",
                "conversation_fold"
            ]
            return modeAllowedTools.filter { readOnlyToolNames.contains($0.name) }
        }
    }
}
