import Foundation

struct ArchitectAdvisorTool: AITool {
    let name = "architect_advisor"
    let description = "Get focused, high-quality architecture advice for the current task. " +
        "Uses Codebase Index context when available. Intended to be called by the Agent during execution."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "task": [
                    "type": "string",
                    "description": "The specific task/question to get architecture guidance for."
                ],
                "constraints": [
                    "type": "string",
                    "description": "Optional constraints (e.g. performance, minimal changes, avoid new deps)."
                ]
            ],
            "required": ["task"]
        ]
    }

    private let aiService: AIService
    private let index: CodebaseIndexProtocol?
    private let projectRoot: URL

    init(aiService: AIService, index: CodebaseIndexProtocol?, projectRoot: URL) {
        self.aiService = aiService
        self.index = index
        self.projectRoot = projectRoot
    }

    func execute(arguments: ToolArguments) async throws -> String {
        let task = try extractTask(from: arguments)
        let explicit = extractExplicitConstraints(from: arguments)
        let context = await ContextBuilder.buildContext(
            userInput: task,
            explicitContext: explicit,
            index: index,
            projectRoot: projectRoot
        )

        let messages = buildAdvisorMessages(task: task)
        let response = try await aiService.sendMessage(AIServiceHistoryRequest(
            messages: messages,
            context: context,
            tools: nil,
            mode: nil,
            projectRoot: projectRoot
        ))
        return response.content ?? "No response received."
    }

    private func extractTask(from arguments: ToolArguments) throws -> String {
        let raw = arguments.raw
        guard let task = raw["task"] as? String,
              !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.aiServiceError("Missing 'task' argument for architect_advisor")
        }
        return task
    }

    private func extractExplicitConstraints(from arguments: ToolArguments) -> String? {
        let raw = arguments.raw
        let constraints = (raw["constraints"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let constraints, !constraints.isEmpty else { return nil }
        return "Constraints:\n\(constraints)"
    }

    private func buildAdvisorMessages(task: String) -> [ChatMessage] {
        let system = ChatMessage(
            role: .system,
            content: """
            You are an expert software architect and senior engineer.

            Goals:
            - Provide focused technical recommendations for the specific task.
            - Prioritize clean architecture, SOLID, SRP, and pragmatic design patterns.
            - Prefer minimal changes that are safe and maintainable.
            - Use provided indexed context; do not perform broad exploratory discovery.
            - Call out risks, tradeoffs, and required tests.

            Output format:
            - Architecture notes (short bullets)
            - Recommended implementation plan (3-6 bullets)
            - Risks and mitigations (bullets)
            - Testing plan (bullets)

            Constraints:
            - Do NOT include chain-of-thought or hidden reasoning.
            - Do NOT invent files/APIs.
            """
        )
        let user = ChatMessage(role: .user, content: task)
        return [system, user]
    }
}
