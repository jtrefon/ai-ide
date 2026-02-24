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
    let delta: OpenRouterChatResponseChunkDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

internal struct OpenRouterChatResponseChunkDelta: Decodable {
    let content: String?
    let toolCalls: [OpenRouterChatResponseChunkToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

internal struct OpenRouterChatResponseChunkToolCall: Decodable {
    let index: Int
    let id: String?
    let type: String?
    let function: OpenRouterChatResponseChunkFunction?
}

internal struct OpenRouterChatResponseChunkFunction: Decodable {
    let name: String?
    let arguments: String?
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
