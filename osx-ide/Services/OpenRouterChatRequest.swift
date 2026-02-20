import Foundation

internal struct OpenRouterChatRequest: Encodable {
    let model: String
    let messages: [OpenRouterChatMessage]
    let maxTokens: Int
    let temperature: Double
    let tools: [[String: Any]]?
    let toolChoice: String?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case tools
        case toolChoice = "tool_choice"
        case stream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(temperature, forKey: .temperature)
        if let tools = tools {
            // Need to wrap nested dictionaries for encoding since [String: Any] is not Encodable
            let data = try JSONSerialization.data(withJSONObject: tools)
            let json = try JSONSerialization.jsonObject(with: data)
            try container.encode(AnyCodable(json), forKey: .tools)
        }

        if let toolChoice, !toolChoice.isEmpty {
            try container.encode(toolChoice, forKey: .toolChoice)
        }

        // Only encode stream if it's true (to avoid unnecessary bytes in request)
        if stream {
            try container.encode(true, forKey: .stream)
        }
    }
}
