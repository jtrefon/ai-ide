import Foundation

internal struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let toolCalls: [AIToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let message: Message
    }
    let choices: [Choice]
}
