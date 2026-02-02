import Foundation

extension OpenRouterAIService {
    internal func buildChatPreparation(
        request: OpenRouterChatHistoryInput
    ) throws -> ChatPreparation {
        let requestId = UUID().uuidString
        let settings = loadSettingsSnapshot()
        try validateSettings(apiKey: settings.apiKey, model: settings.model)

        let systemContent = buildSystemContent(
            input: BuildSystemContentInput(
                systemPrompt: settings.systemPrompt,
                hasTools: request.tools != nil,
                mode: request.mode,
                projectRoot: request.projectRoot,
                reasoningEnabled: settings.reasoningEnabled
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
            toolChoice: toolChoice
        )
    }

    internal func loadSettingsSnapshot() -> SettingsSnapshot {
        let settings = settingsStore.load()
        return SettingsSnapshot(
            apiKey: settings.apiKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            model: settings.model.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            systemPrompt: settings.systemPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            baseURL: settings.baseURL,
            reasoningEnabled: settings.reasoningEnabled
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

    internal func buildSystemContent(input: BuildSystemContentInput) -> String {
        var components: [String] = []
        components.append(buildBaseSystemContent(systemPrompt: input.systemPrompt, hasTools: input.hasTools))

        if let modeSystemAddition = buildModeSystemAddition(mode: input.mode) {
            components.append(modeSystemAddition)
        }

        if let projectRootContext = buildProjectRootContext(projectRoot: input.projectRoot) {
            components.append(projectRootContext)
        }

        if let reasoningPrompt = buildReasoningPromptIfNeeded(
            reasoningEnabled: input.reasoningEnabled,
            mode: input.mode
        ) {
            components.append(reasoningPrompt)
        }

        return components.joined()
    }

    internal func buildBaseSystemContent(systemPrompt: String, hasTools: Bool) -> String {
        if !systemPrompt.isEmpty {
            return systemPrompt
        }

        if hasTools {
            return ToolAwarenessPrompt.systemPrompt
        }

        return "You are a helpful, concise coding assistant."
    }

    internal func buildModeSystemAddition(mode: AIMode?) -> String? {
        guard let mode else { return nil }
        return mode.systemPromptAddition
    }

    internal func buildProjectRootContext(projectRoot: URL?) -> String? {
        guard let projectRoot else { return nil }
        return """

        **IMPORTANT CONTEXT:**
        Project Root: `\(projectRoot.path)`
        Platform: macOS
        All file paths must be relative to the project root or validated absolute paths within it.
        Never use Linux-style paths like /home.
        """
    }

    internal func buildReasoningPromptIfNeeded(reasoningEnabled: Bool, mode: AIMode?) -> String? {
        guard let mode else { return nil }
        if mode != .agent, !reasoningEnabled { return nil }
        return """

        ## Reasoning
        When responding, include a structured reasoning block enclosed in <ide_reasoning>...</ide_reasoning>.
        This block will be shown in a separate, foldable UI panel.

        Requirements:
        - ALWAYS include all six sections in this exact order: Analyze, Research, Plan, Reflect, Action, Delivery.
        - If a section is not applicable, write 'N/A' (do not omit the section).
        - If no action is needed, write 'None' in Action.
        - Delivery MUST start with either 'DONE' or 'NEEDS_WORK'. Use DONE only when the task is fully complete.
        - Keep it concise and actionable; use short bullets or short sentences.
        - Do NOT include code blocks in <ide_reasoning>.
        - Do NOT use placeholders like '...' or copy the format example text verbatim.
        - After </ide_reasoning>, provide the normal user-facing answer as usual (markdown allowed).

        Format example:
        <ide_reasoning>
        Analyze: - ... (write real bullets)
        Research: - ... (write real bullets)
        Plan: - ... (write real bullets)
        Reflect: - ... (write real bullets)
        Action: - ... (write real bullets)
        Delivery: DONE - ... (write real bullets)
        </ide_reasoning>
        """
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
