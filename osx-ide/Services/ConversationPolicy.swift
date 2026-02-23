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
        _ = stage
        let modeAllowedTools = mode.allowedTools(from: availableTools)
        return modeAllowedTools
    }
}
