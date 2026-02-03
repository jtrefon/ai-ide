import Foundation

internal struct OpenRouterChatResponse: Decodable {
    let choices: [OpenRouterChatResponseChoice]
    let usage: OpenRouterChatUsage?
}

internal struct OpenRouterChatUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
