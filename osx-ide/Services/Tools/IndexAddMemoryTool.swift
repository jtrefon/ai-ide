import Foundation

/// Add a memory entry to the Codebase Index.
struct IndexAddMemoryTool: AITool {
    let name = "index_add_memory"
    let description = "Add a memory entry to the Codebase Index. Use for stable long-lived facts " +
        "(project conventions, decisions, APIs)."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "content": [
                    "type": "string",
                    "description": "The memory text to store."
                ],
                "tier": [
                    "type": "string",
                    "description": "Memory tier: shortTerm | midTerm | longTerm (default longTerm)."
                ],
                "category": [
                    "type": "string",
                    "description": "A short category label (e.g. 'architecture', 'api', 'decision')."
                ]
            ],
            "required": ["content", "category"]
        ]
    }

    let index: CodebaseIndexProtocol

    func execute(arguments: ToolArguments) async throws -> String {
        let arguments = arguments.raw
        guard let content = (arguments["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AppError.aiServiceError("Missing 'content' argument for index_add_memory")
        }
        guard let category = (arguments["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !category.isEmpty else {
            throw AppError.aiServiceError("Missing 'category' argument for index_add_memory")
        }

        let tierRaw = (arguments["tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tier = tierRaw.flatMap { $0.isEmpty ? nil : MemoryTier(rawValue: $0) } ?? .longTerm

        let entry = try await index.addMemory(content: content, tier: tier, category: category)
        return "Memory saved: \(entry.id) [\(entry.tier.rawValue)] (category=\(entry.category), protection=\(entry.protectionLevel))"
    }
}
