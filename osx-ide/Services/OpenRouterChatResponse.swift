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

    enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decode(String.self, forKey: .name)

        if let argString = try? container.decode(String.self, forKey: .arguments) {
            arguments = argString
            return
        }

        if let argJSON = try? container.decode(OpenRouterDecodableJSON.self, forKey: .arguments) {
            arguments = argJSON.jsonString()
            return
        }

        arguments = nil
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

private enum OpenRouterDecodableJSON: Decodable {
    case object([String: OpenRouterDecodableJSON])
    case array([OpenRouterDecodableJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: OpenRouterDynamicCodingKey.self) {
            var dict: [String: OpenRouterDecodableJSON] = [:]
            for key in container.allKeys {
                dict[key.stringValue] = try container.decode(OpenRouterDecodableJSON.self, forKey: key)
            }
            self = .object(dict)
            return
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [OpenRouterDecodableJSON] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(OpenRouterDecodableJSON.self))
            }
            self = .array(values)
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Double.self) {
            self = .number(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    func foundationObject() -> Any {
        switch self {
        case .object(let dict):
            return dict.mapValues { $0.foundationObject() }
        case .array(let values):
            return values.map { $0.foundationObject() }
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        }
    }

    func jsonString() -> String? {
        let object = foundationObject()
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

private struct OpenRouterDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
