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
        let arguments = arguments.raw
        guard let task = arguments["task"] as? String,
              !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.aiServiceError("Missing 'task' argument for architect_advisor")
        }
        let constraints = (arguments["constraints"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let explicit = constraints?.isEmpty == false
            ? "Constraints:\n\(constraints!)"
            : nil

        let context = await ContextBuilder.buildContext(
            userInput: task,
            explicitContext: explicit,
            index: index,
            projectRoot: projectRoot
        )

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
        let response = try await aiService.sendMessage(
            [system, user],
            context: context,
            tools: nil,
            mode: nil,
            projectRoot: projectRoot
        )
        return response.content ?? "No response received."
    }
}
