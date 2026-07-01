import Foundation

struct WriteFileToolV2: @unchecked Sendable {
    init() {}

    func definition() -> ToolDefinition {
        ToolDefinition.command(
            name: "write_file",
            desc: "Write content to a file. Creates or overwrites.",
            params: .object(
                properties: [
                    "path": .string(description: "File path", enumValues: nil),
                    "content": .string(description: "File content to write", enumValues: nil),
                ],
                required: ["path", "content"]
            ),
            caps: [.fileWrite],
            se: [.writesFile],
            pm: PromptMaterial(
                concise: "Write to a file.",
                standard: "Write content to a file. Read before writing existing files.",
                comprehensive: "Creates or overwrites files. New files: no read required. Existing files: must read first.",
                successCriteria: nil,
                guidance: nil
            ),
            exec: { [self] in try await self.run(request: $0) }
        )
    }

    func run(request: ToolExecutionRequest) async throws -> ToolFeedback {
        let path = try request.requiredString("path")
        let content = try request.requiredString("content")
        let url = URL(fileURLWithPath: path)
        try Data(content.utf8).write(to: url)
        return .success("Wrote \(path) (\(content.utf8.count)B)")
    }
}
