import Foundation

extension OpenRouterAIService {
    internal func buildChatPreparation(
        request: OpenRouterChatHistoryInput
    ) throws -> ChatPreparation {
        let requestId = UUID().uuidString
        let settings = loadSettingsSnapshot()
        try validateSettings(apiKey: settings.apiKey, model: settings.model)

        let systemContent = try buildSystemContent(
            input: BuildSystemContentInput(
                systemPrompt: settings.systemPrompt,
                hasTools: request.tools?.isEmpty == false,
                toolPromptMode: settings.toolPromptMode,
                mode: request.mode,
                projectRoot: request.projectRoot,
                reasoningMode: settings.reasoningMode,
                stage: request.stage,
                useNativeReasoning: true
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
            nativeReasoningConfiguration: nativeReasoningConfiguration(for: settings.reasoningMode)
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
            throw AppError.aiServiceError("OpenRouter API key is missing.")
        }
        guard !model.isEmpty else {
            throw AppError.aiServiceError("OpenRouter model is not set.")
        }
    }

    internal func buildSystemContent(input: BuildSystemContentInput) throws -> String {
        try SystemPromptAssembler().assemble(
            input: .init(
                systemPromptOverride: input.systemPrompt,
                hasTools: input.hasTools,
                toolPromptMode: input.toolPromptMode,
                mode: input.mode,
                projectRoot: input.projectRoot,
                reasoningMode: input.reasoningMode,
                stage: input.stage,
                includeModelReasoning: !input.useNativeReasoning
            )
        )
    }

    internal func nativeReasoningConfiguration(
        for reasoningMode: ReasoningMode
    ) -> NativeReasoningConfiguration? {
        switch reasoningMode {
        case .none:
            return .init(enabled: false, effort: "none", exclude: true)
        case .model:
            return .init(enabled: true, effort: nil, exclude: true)
        case .agent:
            return .init(enabled: false, effort: "none", exclude: true)
        case .modelAndAgent:
            return .init(enabled: true, effort: nil, exclude: true)
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
