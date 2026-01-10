import Foundation

public struct AgentOrchestrator: Sendable {
    public struct SendRequest: Sendable {
        public let messages: [ChatMessage]
        public let tools: [AITool]

        public init(messages: [ChatMessage], tools: [AITool]) {
            self.messages = messages
            self.tools = tools
        }
    }

    public struct ToolExecutionRequest: Sendable {
        public let toolCalls: [AIToolCall]
        public let tools: [AITool]

        public init(toolCalls: [AIToolCall], tools: [AITool]) {
            self.toolCalls = toolCalls
            self.tools = tools
        }
    }

    public struct Environment: Sendable {
        public let allTools: [AITool]
        public let send: @Sendable (SendRequest) async throws -> AIServiceResponse
        public let executeTools: @Sendable (ToolExecutionRequest) async -> [ChatMessage]
        public let onMessage: @MainActor @Sendable (ChatMessage) -> Void
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
                "git log",
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
        var state = RunState(messages: initialMessages)
        try await runArchitectPhase(state: &state, environment: environment)
        try await runPlannerPhase(state: &state, environment: environment)
        try await runWorkerPhase(state: &state, environment: environment, config: config)
        try await runReviewPhase(state: &state, environment: environment, config: config)
        try await runVerifyPhase(state: &state, environment: environment, config: config)
        appendRoleMessage(
            ChatMessage(
                role: .system,
                content:
                    "You are the Finalizer role. Provide a concise summary: what changed, touched files, verify status, and how to undo (checkpoint/git). Do not call tools."
            ),
            to: &state.messages
        )
        return try await environment.send(SendRequest(messages: state.messages, tools: []))
    }

    private struct RunState {
        var messages: [ChatMessage]
    }

    private struct ToolLoopConfig {
        let tools: [AITool]
        let maxIterations: Int
    }

    private func runArchitectPhase(state: inout RunState, environment: Environment) async throws {
        appendRoleMessage(
            ChatMessage(
                role: .system,
                content:
                    "You are the Architect role. Provide architecture notes and a short implementation plan. Do not call tools."
            ),
            to: &state.messages
        )
        try await emitAssistantContentIfPresent(
            from: try await environment.send(SendRequest(messages: state.messages, tools: [])),
            to: &state.messages,
            environment: environment
        )
    }

    private func runPlannerPhase(state: inout RunState, environment: Environment) async throws {
        appendRoleMessage(
            ChatMessage(
                role: .system,
                content:
                    "You are the Planner role. Create or update a concrete execution plan using the planner tool. Output must be deterministic."
            ),
            to: &state.messages
        )
        let plannerTools = environment.allTools.filter { $0.name == "planner" }
        let response = try await environment.send(
            SendRequest(messages: state.messages, tools: plannerTools))
        if let calls = response.toolCalls, !calls.isEmpty {
            _ = await environment.executeTools(
                ToolExecutionRequest(toolCalls: calls, tools: plannerTools))
        }
    }

    private func runWorkerPhase(
        state: inout RunState, environment: Environment, config: Configuration
    ) async throws {
        appendRoleMessage(
            ChatMessage(
                role: .system,
                content:
                    "You are the Worker role. Implement the plan. Prefer proposing changes via patch sets; avoid direct writes unless necessary. Use tools."
            ),
            to: &state.messages
        )
        let initial = try await environment.send(
            SendRequest(messages: state.messages, tools: environment.allTools))
        try await runToolLoop(
            state: &state, environment: environment, initialResponse: initial,
            config: ToolLoopConfig(
                tools: environment.allTools, maxIterations: config.maxWorkerToolIterations))
    }

    private func runReviewPhase(
        state: inout RunState, environment: Environment, config: Configuration
    ) async throws {
        appendRoleMessage(
            ChatMessage(
                role: .system,
                content:
                    "You are the QA role. Review the proposed patch set(s) and tool outputs. If fixes are needed, propose edits. Otherwise, proceed to apply the patch set."
            ),
            to: &state.messages
        )
        let initial = try await environment.send(
            SendRequest(messages: state.messages, tools: environment.allTools))
        try await runToolLoop(
            state: &state, environment: environment, initialResponse: initial,
            config: ToolLoopConfig(
                tools: environment.allTools, maxIterations: config.maxReviewIterations))
    }

    private func runVerifyPhase(
        state: inout RunState, environment: Environment, config: Configuration
    ) async throws {
        appendRoleMessage(
            ChatMessage(
                role: .system,
                content:
                    "You are the Verifier role. Run a small set of allowlisted commands to verify changes. Do not run long-lived commands."
            ),
            to: &state.messages
        )
        let verifyTools = allowlistedVerifyTools(
            from: environment.allTools, allowedPrefixes: config.verifyAllowedCommandPrefixes)
        let initial = try await environment.send(
            SendRequest(messages: state.messages, tools: verifyTools))
        try await runToolLoop(
            state: &state, environment: environment, initialResponse: initial,
            config: ToolLoopConfig(tools: verifyTools, maxIterations: config.maxVerifyIterations))
    }

    private func appendRoleMessage(_ message: ChatMessage, to messages: inout [ChatMessage]) {
        messages.append(message)
    }

    private func emitAssistantContentIfPresent(
        from response: AIServiceResponse, to messages: inout [ChatMessage], environment: Environment
    ) async throws {
        if let content = response.content {
            let split = ChatPromptBuilder.splitReasoning(from: content)
            let msg = ChatMessage(
                role: .assistant, content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning))
            await environment.onMessage(msg)
            messages.append(msg)
        }
    }

    private func runToolLoop(
        state: inout RunState, environment: Environment, initialResponse: AIServiceResponse,
        config: ToolLoopConfig
    ) async throws {
        var response = initialResponse
        var iterations = 0

        while let toolCalls = response.toolCalls, !toolCalls.isEmpty,
            iterations < config.maxIterations
        {
            iterations += 1

            let split = ChatPromptBuilder.splitReasoning(from: response.content ?? "")
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning),
                tool: ChatMessageToolContext(toolCalls: toolCalls)
            )
            await environment.onMessage(assistantMsg)
            state.messages.append(assistantMsg)

            let results = await environment.executeTools(
                ToolExecutionRequest(toolCalls: toolCalls, tools: config.tools))
            for msg in results {
                await environment.onMessage(msg)
                state.messages.append(msg)
            }

            response = try await environment.send(
                SendRequest(messages: state.messages, tools: config.tools))
        }
    }

    private func allowlistedVerifyTools(from tools: [AITool], allowedPrefixes: [String]) -> [AITool]
    {
        tools.map { tool in
            if tool.name == "run_command", let streaming = tool as? any AIToolProgressReporting {
                return AllowlistedRunCommandTool(base: streaming, allowedPrefixes: allowedPrefixes)
            }
            return tool
        }
    }
}
