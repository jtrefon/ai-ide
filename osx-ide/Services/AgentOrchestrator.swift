import Foundation

public struct AgentOrchestrator: Sendable {
    public struct Environment: Sendable {
        public let allTools: [AITool]
        public let send: @Sendable (_ messages: [ChatMessage], _ tools: [AITool]) async throws -> AIServiceResponse
        public let executeTools: @Sendable (_ toolCalls: [AIToolCall], _ tools: [AITool]) async -> [ChatMessage]
        public let onMessage: @MainActor @Sendable (ChatMessage) -> Void

        public init(
            allTools: [AITool],
            send: @Sendable @escaping (_ messages: [ChatMessage], _ tools: [AITool]) async throws -> AIServiceResponse,
            executeTools: @Sendable @escaping (_ toolCalls: [AIToolCall], _ tools: [AITool]) async -> [ChatMessage],
            onMessage: @MainActor @Sendable @escaping (ChatMessage) -> Void
        ) {
            self.allTools = allTools
            self.send = send
            self.executeTools = executeTools
            self.onMessage = onMessage
        }
    }

    public struct Configuration: Sendable {
        public let maxWorkerToolIterations: Int
        public let maxReviewIterations: Int
        public let maxVerifyIterations: Int
        public let verifyAllowedCommandPrefixes: [String]

        public init(
            maxWorkerToolIterations: Int = 12,
            maxReviewIterations: Int = 3,
            maxVerifyIterations: Int = 3,
            verifyAllowedCommandPrefixes: [String] = [
                "xcodebuild ",
                "swift test",
                "swift-format ",
                "swiftlint ",
                "git status",
                "git diff",
                "git log"
            ]
        ) {
            self.maxWorkerToolIterations = max(1, maxWorkerToolIterations)
            self.maxReviewIterations = max(1, maxReviewIterations)
            self.maxVerifyIterations = max(1, maxVerifyIterations)
            self.verifyAllowedCommandPrefixes = verifyAllowedCommandPrefixes
        }
    }

    public func run(
        initialMessages: [ChatMessage],
        environment: Environment,
        config: Configuration = Configuration()
    ) async throws -> AIServiceResponse {
        var messages = initialMessages

        appendRoleMessage(
            ChatMessage(role: .system, content: "You are the Architect role. Provide architecture notes and a short implementation plan. Do not call tools."),
            to: &messages
        )
        try await emitAssistantContentIfPresent(
            from: try await environment.send(messages, []),
            to: &messages,
            environment: environment
        )

        appendRoleMessage(
            ChatMessage(role: .system, content: "You are the Planner role. Create or update a concrete execution plan using the planner tool. Output must be deterministic."),
            to: &messages
        )
        let plannerTools = environment.allTools.filter { $0.name == "planner" }
        let plannerResponse = try await environment.send(messages, plannerTools)
        if let calls = plannerResponse.toolCalls, !calls.isEmpty {
            _ = await environment.executeTools(calls, plannerTools)
        }

        appendRoleMessage(
            ChatMessage(role: .system, content: "You are the Worker role. Implement the plan. Prefer proposing changes via patch sets; avoid direct writes unless necessary. Use tools."),
            to: &messages
        )
        try await runToolLoop(
            initialResponse: try await environment.send(messages, environment.allTools),
            tools: environment.allTools,
            maxIterations: config.maxWorkerToolIterations,
            messages: &messages,
            environment: environment
        )

        appendRoleMessage(
            ChatMessage(role: .system, content: "You are the QA role. Review the proposed patch set(s) and tool outputs. If fixes are needed, propose edits. Otherwise, proceed to apply the patch set."),
            to: &messages
        )
        try await runToolLoop(
            initialResponse: try await environment.send(messages, environment.allTools),
            tools: environment.allTools,
            maxIterations: config.maxReviewIterations,
            messages: &messages,
            environment: environment
        )

        appendRoleMessage(
            ChatMessage(role: .system, content: "You are the Verifier role. Run a small set of allowlisted commands to verify changes. Do not run long-lived commands."),
            to: &messages
        )
        let verifyTools = allowlistedVerifyTools(from: environment.allTools, allowedPrefixes: config.verifyAllowedCommandPrefixes)
        try await runToolLoop(
            initialResponse: try await environment.send(messages, verifyTools),
            tools: verifyTools,
            maxIterations: config.maxVerifyIterations,
            messages: &messages,
            environment: environment
        )

        appendRoleMessage(
            ChatMessage(role: .system, content: "You are the Finalizer role. Provide a concise summary: what changed, touched files, verify status, and how to undo (checkpoint/git). Do not call tools."),
            to: &messages
        )
        return try await environment.send(messages, [])
    }

    private func appendRoleMessage(_ message: ChatMessage, to messages: inout [ChatMessage]) {
        messages.append(message)
    }

    private func emitAssistantContentIfPresent(from response: AIServiceResponse, to messages: inout [ChatMessage], environment: Environment) async throws {
        if let content = response.content {
            let split = ChatPromptBuilder.splitReasoning(from: content)
            let msg = ChatMessage(role: .assistant, content: split.content, context: ChatMessageContentContext(reasoning: split.reasoning))
            await environment.onMessage(msg)
            messages.append(msg)
        }
    }

    private func runToolLoop(
        initialResponse: AIServiceResponse,
        tools: [AITool],
        maxIterations: Int,
        messages: inout [ChatMessage],
        environment: Environment
    ) async throws {
        var response = initialResponse
        var iterations = 0

        while let toolCalls = response.toolCalls, !toolCalls.isEmpty, iterations < maxIterations {
            iterations += 1

            let split = ChatPromptBuilder.splitReasoning(from: response.content ?? "")
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning),
                tool: ChatMessageToolContext(toolCalls: toolCalls)
            )
            await environment.onMessage(assistantMsg)
            messages.append(assistantMsg)

            let results = await environment.executeTools(toolCalls, tools)
            for msg in results {
                await environment.onMessage(msg)
                messages.append(msg)
            }

            response = try await environment.send(messages, tools)
        }
    }

    private func allowlistedVerifyTools(from tools: [AITool], allowedPrefixes: [String]) -> [AITool] {
        tools.map { tool in
            if tool.name == "run_command", let streaming = tool as? any AIToolProgressReporting {
                return AllowlistedRunCommandTool(base: streaming, allowedPrefixes: allowedPrefixes)
            }
            return tool
        }
    }
}
