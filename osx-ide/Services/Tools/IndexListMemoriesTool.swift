import Foundation

/// List memories from the Codebase Index.
struct IndexListMemoriesTool: AITool {
    let name = "index_list_memories"
    let description = "List stored memories from the Codebase Index. Optionally filter by tier." +
        " Returns newest-first with id, tier, category, timestamp, and content."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "tier": [
                    "type": "string",
                    "description": "Optional memory tier filter: shortTerm | midTerm | longTerm."
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max results (default 25, max 200)."
                ]
            ],
            "required": []
        ]
    }

    let index: CodebaseIndexProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        let tierRaw = (arguments["tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(200, arguments["limit"] as? Int ?? 25))

        let tier: MemoryTier?
        if let tierRaw, !tierRaw.isEmpty {
            tier = MemoryTier(rawValue: tierRaw)
            if tier == nil {
                throw AppError.aiServiceError("Invalid 'tier' argument for index_list_memories. Use: shortTerm | midTerm | longTerm")
            }
        } else {
            tier = nil
        }

        let results = try await index.getMemories(tier: tier)
        if results.isEmpty {
            return "No memories found."
        }

        let lines = results.prefix(limit).map { entry in
            "\(entry.id) [\(entry.tier.rawValue)] (category=\(entry.category), protection=\(entry.protectionLevel), ts=\(ISO8601DateFormatter().string(from: entry.timestamp))):\n\(entry.content)"
        }
        return lines.joined(separator: "\n\n")
    }
}
