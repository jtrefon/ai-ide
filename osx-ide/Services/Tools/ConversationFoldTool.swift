import Foundation

struct ConversationFoldTool: AITool {
    let name: String = "conversation_fold"
    let description: String = "Access folded (condensed) conversation context stored outside the active prompt context. Supports listing folds and reading a fold by id."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "description": "One of: list, read",
                    "enum": ["list", "read"],
                ],
                "id": [
                    "type": "string",
                    "description": "Fold id (required for action=read)",
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max number of folds to return (action=list)",
                ],
            ],
            "required": ["action"],
        ]
    }

    let projectRoot: URL

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let action = arguments["action"] as? String else {
            throw AppError.aiServiceError("Missing 'action' argument for conversation_fold")
        }

        let store = ConversationFoldStore(projectRoot: projectRoot)

        switch action {
        case "list":
            let limit = arguments["limit"] as? Int ?? 50
            let entries = try await store.list(limit: limit)
            let payload = entries.map { [
                "id": $0.id,
                "summary": $0.summary,
                "createdAt": ISO8601DateFormatter().string(from: $0.createdAt),
            ] }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            return String(decoding: data, as: UTF8.self)

        case "read":
            guard let id = arguments["id"] as? String, !id.isEmpty else {
                throw AppError.aiServiceError("Missing 'id' argument for conversation_fold (action=read)")
            }
            let content = try await store.read(id: id)
            return content

        default:
            throw AppError.aiServiceError("Invalid 'action' for conversation_fold: \(action)")
        }
    }
}
