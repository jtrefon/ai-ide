import Foundation

struct ToolExecutionEnvelope: Codable, Sendable {
    let status: ToolExecutionStatus
    let message: String
    let payload: String?
    let toolName: String
    let toolCallId: String
    let targetFile: String?

    func encodedString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            let fallback = [
                "status": status.rawValue,
                "message": message,
                "toolName": toolName,
                "toolCallId": toolCallId,
                "targetFile": targetFile ?? ""
            ]
            return (try? JSONSerialization.data(withJSONObject: fallback, options: [.sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) }
                ?? "{\"status\":\"\(status.rawValue)\",\"message\":\"\(message)\"}"
        }
        return string
    }

    static func decode(from content: String) -> ToolExecutionEnvelope? {
        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolExecutionEnvelope.self, from: data)
    }
}
