import Foundation

public struct AIToolCall: Codable, @unchecked Sendable {
    public let id: String
    public let type: String
    public let name: String
    public let arguments: [String: Any]

    public enum CodingKeys: String, CodingKey {
        case id
        case type
        case function
    }

    public enum FunctionCodingKeys: String, CodingKey {
        case name
        case arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        type = (try? container.decode(String.self, forKey: .type)) ?? "function"

        let functionContainer = try container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
        name = try functionContainer.decode(String.self, forKey: .name)

        arguments = Self.decodeArguments(from: functionContainer, toolName: name)
    }

    init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.type = "function"
        self.name = name
        self.arguments = arguments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)

        var functionContainer = container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
        try functionContainer.encode(name, forKey: .name)

        let jsonData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        try functionContainer.encode(jsonString, forKey: .arguments)
    }

    private static func decodeArguments(
        from container: KeyedDecodingContainer<FunctionCodingKeys>,
        toolName: String
    ) -> [String: Any] {
        if let argumentsString = try? container.decode(String.self, forKey: .arguments) {
            if let dict = parseJSONObjectString(argumentsString) {
                return dict
            }
            if let array = parseJSONArrayString(argumentsString),
               toolName == "write_files" {
                let fileEntries = array.compactMap { $0 as? [String: Any] }
                if !fileEntries.isEmpty {
                    return ["files": fileEntries]
                }
            }
            let trimmed = argumentsString.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [:] : ["_raw_args_chunk": argumentsString]
        }

        if let jsonValue = try? container.decode(DecodableJSON.self, forKey: .arguments) {
            let object = jsonValue.foundationObject()
            if let dict = object as? [String: Any] {
                return dict
            }
            if let array = object as? [Any], toolName == "write_files" {
                let fileEntries = array.compactMap { $0 as? [String: Any] }
                if !fileEntries.isEmpty {
                    return ["files": fileEntries]
                }
            }
            if let serialized = jsonValue.jsonString(),
               !serialized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ["_raw_args_chunk": serialized]
            }
        }

        return [:]
    }

    private static func parseJSONObjectString(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func parseJSONArrayString(_ raw: String) -> [Any]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let array = object as? [Any] else {
            return nil
        }
        return array
    }
}

private enum DecodableJSON: Decodable {
    case object([String: DecodableJSON])
    case array([DecodableJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: DecodableJSON] = [:]
            for key in container.allKeys {
                dict[key.stringValue] = try container.decode(DecodableJSON.self, forKey: key)
            }
            self = .object(dict)
            return
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [DecodableJSON] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(DecodableJSON.self))
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

private struct DynamicCodingKey: CodingKey {
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
