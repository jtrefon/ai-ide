import Foundation

struct ReadFileToolV2: @unchecked Sendable {
    let governor: ResourceGovernor?

    init(governor: ResourceGovernor? = nil) {
        self.governor = governor
    }

    func definition() -> ToolDefinition {
        ToolDefinition.query(
            name: "read_file",
            desc: "Read file contents with line numbers.",
            params: .object(
                properties: [
                    "path": .string(description: "File path", enumValues: nil),
                    "start_line": .integer(desc: "1-based start line"),
                    "end_line": .integer(desc: "1-based end line"),
                ],
                required: ["path"]
            ),
            caps: [.fileRead],
            se: .readsFile,
            cf: "text",
            pm: PromptMaterial(
                concise: "Read a file.",
                standard: "Read file with line-numbered output.",
                comprehensive: "Reads a file. Use start_line/end_line for large files.",
                successCriteria: nil,
                guidance: nil
            ),
            exec: { [self] in try await self.run(request: $0) }
        )
    }

    func run(request: ToolExecutionRequest) async throws -> ToolFeedback {
        let path = try request.requiredString("path")
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? "<binary>"
        return .success(
            "Read \(url.lastPathComponent) (\(data.count)B)",
            text: text,
            meta: ["bytes": String(data.count)]
        )
    }
}
