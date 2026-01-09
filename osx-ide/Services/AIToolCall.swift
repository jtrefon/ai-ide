import Foundation

public struct AIToolCall: Codable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let arguments: [String: Any]

    public enum CodingKeys: String, CodingKey {
        case id
        case function
    }

    public enum FunctionCodingKeys: String, CodingKey {
        case name
        case arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        let functionContainer = try container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
        name = try functionContainer.decode(String.self, forKey: .name)

        let argumentsString = try functionContainer.decode(String.self, forKey: .arguments)
        if let data = argumentsString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = dict
        } else {
            arguments = [:]
        }
    }

    init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)

        var functionContainer = container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
        try functionContainer.encode(name, forKey: .name)

        let jsonData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        try functionContainer.encode(jsonString, forKey: .arguments)
    }
}
