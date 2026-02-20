import Foundation

internal struct OpenRouterChatResponse: Decodable {
    let choices: [OpenRouterChatResponseChoice]
    let usage: OpenRouterChatUsage?
}

/// Streaming chunk response from OpenRouter
internal struct OpenRouterChatResponseChunk: Decodable {
    let choices: [OpenRouterChatResponseChunkChoice]
}

internal struct OpenRouterChatResponseChunkChoice: Decodable {
    let delta: OpenRouterChatResponseMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
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
