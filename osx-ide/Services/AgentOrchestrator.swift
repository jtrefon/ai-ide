import Foundation

public struct AgentOrchestrator: Sendable {
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

    public init() {}

    public func run(
        conversationId: String,
        projectRoot: URL,
        initialMessages: [ChatMessage],
        allTools: [AITool],
        send: @Sendable @escaping (_ messages: [ChatMessage], _ tools: [AITool]) async throws -> AIServiceResponse,
        executeTools: @Sendable @escaping (_ toolCalls: [AIToolCall], _ tools: [AITool]) async -> [ChatMessage],
        onMessage: @MainActor @Sendable @escaping (ChatMessage) -> Void,
        config: Configuration = Configuration()
    ) async throws -> AIServiceResponse {
        var messages = initialMessages

        let architect = ChatMessage(
            role: .system,
            content: "You are the Architect role. Provide architecture notes and a short implementation plan. Do not call tools."
        )
        messages.append(architect)
        let architectResponse = try await send(messages, [])
        if let content = architectResponse.content {
            let split = ChatPromptBuilder.splitReasoning(from: content)
            let msg = ChatMessage(role: .assistant, content: split.content, context: ChatMessageContentContext(reasoning: split.reasoning))
            await onMessage(msg)
            messages.append(msg)
        }

        let planner = ChatMessage(
            role: .system,
            content: "You are the Planner role. Create or update a concrete execution plan using the planner tool. Output must be deterministic."
        )
        let plannerTools = allTools.filter { $0.name == "planner" }
        messages.append(planner)
        let plannerResponse = try await send(messages, plannerTools)
        if let calls = plannerResponse.toolCalls, !calls.isEmpty {
            _ = await executeTools(calls, plannerTools)
        }

        let worker = ChatMessage(
            role: .system,
            content: "You are the Worker role. Implement the plan. Prefer proposing changes via patch sets; avoid direct writes unless necessary. Use tools."
        )

        messages.append(worker)
        var currentResponse = try await send(messages, allTools)
        var workerIterations = 0
        while let toolCalls = currentResponse.toolCalls, !toolCalls.isEmpty, workerIterations < config.maxWorkerToolIterations {
            workerIterations += 1
            let split = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "")
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning),
                tool: ChatMessageToolContext(toolCalls: toolCalls)
            )
            await onMessage(assistantMsg)
            messages.append(assistantMsg)

            let results = await executeTools(toolCalls, allTools)
            for msg in results {
                await onMessage(msg)
                messages.append(msg)
            }

            currentResponse = try await send(messages, allTools)
        }

        let qa = ChatMessage(
            role: .system,
            content: "You are the QA role. Review the proposed patch set(s) and tool outputs. If fixes are needed, propose edits. Otherwise, proceed to apply the patch set."
        )

        messages.append(qa)
        var reviewResponse = try await send(messages, allTools)
        var reviewIterations = 0
        while let toolCalls = reviewResponse.toolCalls, !toolCalls.isEmpty, reviewIterations < config.maxReviewIterations {
            reviewIterations += 1
            let split = ChatPromptBuilder.splitReasoning(from: reviewResponse.content ?? "")
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning),
                tool: ChatMessageToolContext(toolCalls: toolCalls)
            )
            await onMessage(assistantMsg)
            messages.append(assistantMsg)

            let results = await executeTools(toolCalls, allTools)
            for msg in results {
                await onMessage(msg)
                messages.append(msg)
            }

            reviewResponse = try await send(messages, allTools)
        }

        let verify = ChatMessage(
            role: .system,
            content: "You are the Verifier role. Run a small set of allowlisted commands to verify changes. Do not run long-lived commands."
        )

        let verifyTools: [AITool] = allTools.map { tool in
            if tool.name == "run_command", let streaming = tool as? any AIToolProgressReporting {
                return AllowlistedRunCommandTool(base: streaming, allowedPrefixes: config.verifyAllowedCommandPrefixes)
            }
            return tool
        }

        messages.append(verify)
        var verifyResponse = try await send(messages, verifyTools)
        var verifyIterations = 0
        while let toolCalls = verifyResponse.toolCalls, !toolCalls.isEmpty, verifyIterations < config.maxVerifyIterations {
            verifyIterations += 1
            let split = ChatPromptBuilder.splitReasoning(from: verifyResponse.content ?? "")
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: split.content,
                context: ChatMessageContentContext(reasoning: split.reasoning),
                tool: ChatMessageToolContext(toolCalls: toolCalls)
            )
            await onMessage(assistantMsg)
            messages.append(assistantMsg)

            let results = await executeTools(toolCalls, verifyTools)
            for msg in results {
                await onMessage(msg)
                messages.append(msg)
            }

            verifyResponse = try await send(messages, verifyTools)
        }

        let finalizer = ChatMessage(
            role: .system,
            content: "You are the Finalizer role. Provide a concise summary: what changed, touched files, verify status, and how to undo (checkpoint/git). Do not call tools."
        )

        messages.append(finalizer)
        return try await send(messages, [])
    }
}
