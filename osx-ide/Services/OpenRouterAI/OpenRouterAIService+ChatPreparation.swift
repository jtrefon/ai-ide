import Foundation

extension OpenRouterAIService {
    internal func buildChatPreparation(
        request: OpenRouterChatHistoryInput
    ) async throws -> ChatPreparation {
        let requestId = UUID().uuidString
        let settings = loadSettingsSnapshot()
        try validateSettings(apiKey: settings.apiKey, model: settings.model)

        let systemContent = try await buildSystemContent(
            input: BuildSystemContentInput(
                systemPrompt: settings.systemPrompt,
                hasTools: request.tools?.isEmpty == false,
                toolPromptMode: settings.toolPromptMode,
                mode: request.mode,
                projectRoot: request.projectRoot,
                reasoningMode: settings.reasoningMode,
                stage: request.stage,
                useNativeReasoning: supportsNativeReasoning,
                conversationId: request.conversationId
            )
        )

        let finalMessages = buildFinalMessages(
            systemContent: systemContent,
            context: request.context,
            messages: request.messages
        )

        let toolDefinitions = buildToolDefinitions(tools: request.tools)
        let toolChoice = toolDefinitions?.isEmpty == false ? "auto" : nil

        return ChatPreparation(
            requestId: requestId,
            settings: settings,
            finalMessages: finalMessages,
            toolDefinitions: toolDefinitions,
            toolChoice: toolChoice,
            nativeReasoningConfiguration: supportsNativeReasoning
                ? nativeReasoningConfiguration(for: settings.reasoningMode)
                : nil
        )
    }

    internal func loadSettingsSnapshot() -> SettingsSnapshot {
        let settings = settingsStore.load(includeApiKey: true)
        return SettingsSnapshot(
            apiKey: settings.apiKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            model: settings.model.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            systemPrompt: settings.systemPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            baseURL: settings.baseURL,
            reasoningMode: settings.reasoningMode,
            toolPromptMode: settings.toolPromptMode
        )
    }

    internal func validateSettings(apiKey: String, model: String) throws {
        guard !apiKey.isEmpty else {
            throw AppError.aiServiceError("\(providerName) API key is missing.")
        }
        guard !model.isEmpty else {
            throw AppError.aiServiceError("\(providerName) model is not set.")
        }
    }

    internal func buildSystemContent(input: BuildSystemContentInput) async throws -> String {
        let activeTaskContext: String?
        if input.hasTools, let conversationId = input.conversationId {
            let store = ConversationPlanStore.shared
            if let plan = await store.getPlan(conversationId: conversationId),
               let activeItem = plan.activeItem,
               activeItem.status == .active {
                let completed = plan.items.filter { $0.status == .completed || $0.status == .blocked }.count
                let total = plan.items.count
                activeTaskContext = """
                ## Current Task

                You are working on task \(completed + 1) of \(total) in a structured plan.

                **Task:** \(activeItem.description)
                **Purpose:** \(activeItem.purpose)
                **Context:** \(activeItem.context.joined(separator: ", "))
                **Done when:** \(activeItem.doneCriteria)

                Use `task_report` for mid-task checkpoints. Use `task_signoff` when this task is complete — the framework will inject the next task's context automatically.
                """
            } else {
                activeTaskContext = nil
            }
        } else {
            activeTaskContext = nil
        }

        return try SystemPromptAssembler().assemble(
            input: .init(
                systemPromptOverride: input.systemPrompt,
                hasTools: input.hasTools,
                toolPromptMode: input.toolPromptMode,
                mode: input.mode,
                projectRoot: input.projectRoot,
                reasoningMode: input.reasoningMode,
                stage: input.stage,
                includeModelReasoning: !input.useNativeReasoning,
                activeTaskContext: activeTaskContext
            )
        )
    }

    internal func nativeReasoningConfiguration(
        for reasoningMode: ReasoningMode
    ) -> NativeReasoningConfiguration? {
        let effort = ReasoningIntensity.current.apiEffortValue
        switch reasoningMode {
        case .none:
            return .init(enabled: false, effort: "none", exclude: true)
        case .model:
            return .init(enabled: true, effort: effort, exclude: true)
        case .agent:
            return .init(enabled: false, effort: "none", exclude: true)
        case .modelAndAgent:
            return .init(enabled: true, effort: effort, exclude: true)
        }
    }

    internal func buildFinalMessages(
        systemContent: String,
        context: String?,
        messages: [OpenRouterChatMessage]
    ) -> [OpenRouterChatMessage] {
        var finalMessages = [OpenRouterChatMessage(role: "system", content: systemContent)]

        if let context, !context.isEmpty {
            finalMessages.append(OpenRouterChatMessage(
                role: "user",
                content: "Context:\n\(context)"
            ))
        }

        finalMessages.append(contentsOf: messages)
        return finalMessages
    }

    internal func buildToolDefinitions(tools: [AITool]?) -> [[String: Any]]? {
        tools?.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters
                ]
            ]
        }
    }
}
