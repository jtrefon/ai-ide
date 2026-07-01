import Foundation

struct ParsedToolCall: Sendable, Codable {
    let id: String
    let toolName: String
    let arguments: [String: ToolValue]

    init(id: String, toolName: String, args: [String: ToolValue]) {
        self.id = id
        self.toolName = toolName
        self.arguments = args
    }

    /// Parse a tool call from raw JSON. Handles truncated/incomplete JSON gracefully.
    static func from(json: [String: Any]) throws -> ParsedToolCall {
        guard let id = json["id"] as? String ?? (json["id"] as? NSString) as String? else {
            throw ParsedToolCallError.missingField("id")
        }

        let toolName: String
        if let fn = json["function"] as? [String: Any] {
            guard let name = fn["name"] as? String else {
                throw ParsedToolCallError.missingField("function.name")
            }
            toolName = name
        } else {
            guard let name = json["name"] as? String ?? (json["name"] as? NSString) as String? else {
                throw ParsedToolCallError.missingField("name")
            }
            toolName = name
        }

        // Parse arguments — they can be a JSON string or a JSON object
        // Handle PARTIAL/TRUNCATED arguments gracefully — store raw string
        // instead of crashing, so tool can attempt recovery
        let args: [String: ToolValue]
        if let fn = json["function"] as? [String: Any],
           let argsString = fn["arguments"] as? String {
            if let argsData = argsString.data(using: .utf8),
               let argsJSON = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                args = ToolValue.from(dict: argsJSON)
            } else {
                // Truncated or malformed JSON — store raw chunk for recovery
                args = ["_raw_args_chunk": .string(argsString)]
            }
        } else if let d = json["arguments"] as? [String: Any] {
            args = ToolValue.from(dict: d)
        } else {
            args = [:]
        }

        return ParsedToolCall(id: id, toolName: toolName, args: args)
    }

    var signature: String {
        arguments.map { "\($0)=\($1)" }.sorted().joined(separator: "&")
    }
}

enum ParsedToolCallError: LocalizedError, Sendable {
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let f): return "Missing: " + f
        }
    }
}
