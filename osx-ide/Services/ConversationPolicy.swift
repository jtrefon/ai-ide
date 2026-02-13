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
        if mode == .chat {
            return []
        }

        guard let stage else {
            return availableTools
        }

        switch stage {
        case .strategic_planning, .tactical_planning:
            return readOnlyTools(from: availableTools)
        case .qa_tool_output_review, .qa_quality_review:
            return readOnlyTools(from: availableTools)
        default:
            return availableTools
        }
    }

    private func readOnlyTools(from tools: [AITool]) -> [AITool] {
        let allowed = Set([
            "index_find_files",
            "index_list_files",
            "index_search_text",
            "index_read_file",
            "index_search_symbols"
        ])
        return tools.filter { allowed.contains($0.name) }
    }
}
