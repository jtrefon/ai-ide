import Foundation

internal struct OpenRouterChatMessage: Encodable {
    let role: String
    let content: String?
    let toolCallID: String?
    let toolCalls: [AIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    init(role: String, content: String? = nil, toolCallID: String? = nil, toolCalls: [AIToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }
}
