import Foundation

protocol ConversationPolicyProtocol {
    func allowedTools(
        for stage: AIRequestStage?,
        mode: AIMode,
        from availableTools: [AITool]
    ) -> [AITool]
}

final class ConversationPolicy: ConversationPolicyProtocol {
    private let readOnlyToolNames: Set<String> = [
        "index_find_files",
        "index_list_files",
        "index_search_text",
        "index_read_file",
        "index_search_symbols",
        "read_file",
        "list_files",
        "conversation_fold"
    ]

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
            return filterReadOnlyTools(from: modeAllowedTools)
            
        case .initial_response:
            // Preserve full execution capability for the agent's first response.
            return modeAllowedTools
            
        case .tool_loop, .final_response:
            // All tools for execution stages
            return modeAllowedTools
            
        case .warmup, .other:
            // Default to read-only for unknown stages
            return filterReadOnlyTools(from: modeAllowedTools)
        }
    }

    private func filterReadOnlyTools(from tools: [AITool]) -> [AITool] {
        tools.filter { readOnlyToolNames.contains($0.name) }
    }
}
