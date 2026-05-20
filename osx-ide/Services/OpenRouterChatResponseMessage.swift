import Foundation

internal struct OpenRouterChatResponseMessage: Decodable {
    let content: String?
    let toolCalls: [AIToolCall]?
    let reasoning: String?
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
        case reasoning
        case reasoningContent = "reasoning_content"
    }
}
