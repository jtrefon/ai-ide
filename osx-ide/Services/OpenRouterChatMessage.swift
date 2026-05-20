import Foundation

internal struct OpenRouterChatMessage: Encodable {
    let role: String
    let content: String?
    let toolCallID: String?
    let toolCalls: [AIToolCall]?
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
        case reasoningContent = "reasoning_content"
    }

    init(role: String, content: String? = nil, toolCallID: String? = nil, toolCalls: [AIToolCall]? = nil, reasoningContent: String? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.reasoningContent = reasoningContent
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
    }
}
