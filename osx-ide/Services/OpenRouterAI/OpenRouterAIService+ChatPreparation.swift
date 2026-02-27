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
                hasTools: request.tools?.isEmpty == false,
                toolPromptMode: settings.toolPromptMode,
                mode: request.mode,
                projectRoot: request.projectRoot,
                reasoningEnabled: settings.reasoningEnabled,
                stage: request.stage
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
            reasoningEnabled: settings.reasoningEnabled,
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

    internal func buildSystemContent(input: BuildSystemContentInput) -> String {
        var components: [String] = []
        components.append(
            buildBaseSystemContent(
                systemPrompt: input.systemPrompt,
                hasTools: input.hasTools,
                toolPromptMode: input.toolPromptMode
            )
        )

        if let modeSystemAddition = buildModeSystemAddition(mode: input.mode) {
            components.append(modeSystemAddition)
        }

        if let projectRootContext = buildProjectRootContext(projectRoot: input.projectRoot) {
            components.append(projectRootContext)
        }

        if let reasoningPrompt = buildReasoningPromptIfNeeded(
            reasoningEnabled: input.reasoningEnabled,
            mode: input.mode,
            stage: input.stage
        ) {
            components.append(reasoningPrompt)
        }

        return components.joined(separator: "\n\n")
    }

    internal func buildBaseSystemContent(systemPrompt: String, hasTools: Bool, toolPromptMode: ToolPromptMode) -> String {
        if !systemPrompt.isEmpty {
            return systemPrompt
        }

        if hasTools {
            switch toolPromptMode {
            case .fullStatic:
                return ToolAwarenessPrompt.systemPrompt
            case .concise:
                return ToolAwarenessPrompt.structuredToolCallingSystemPrompt
            }
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

    internal func buildReasoningPromptIfNeeded(reasoningEnabled: Bool, mode: AIMode?, stage: AIRequestStage?) -> String? {
        guard let mode else { return nil }
        if mode != .agent || !reasoningEnabled { return nil }

        if stage == .tool_loop {
            return """

            ## Reasoning
            During tool loop execution you MUST follow the pair-programming cadence:

            - Always emit a <ide_reasoning> block using the Reflection/Planning/Continuity schema.
            - Each bullet is a single clause referencing concrete files/functions/components.
            - After </ide_reasoning>, write one sentence covering Done → Next → Path.
            - Immediately return tool calls that implement the “Planning” How/Where instructions without asking the user for confirmation.
            - Keep everything terse and technical—no filler, no repeated blocks, no pseudo-tool JSON.

            Format example:
            <ide_reasoning>
            Reflection:
            - What: <result>
            - Where: <file/component>
            - How: <tool/operation>
            Planning:
            - What: <next objective>
            - Where: <exact locus>
            - How: <tool/action>
            Continuity: <risks/invariants>
            </ide_reasoning>
            Hardened X in File.swift; next adjust Tests.swift via write_file.
            """
        }

        return """

        ## Reasoning
        Always include a structured <ide_reasoning> block using the Reflection/Planning/Continuity schema. This block is rendered separately for the user, so keep it dense and technical.

        - Reflection: three bullets (What/Where/How) describing the latest outcome or blocker. Reference concrete files, components, or commands.
        - Planning: three bullets (What/Where/How) detailing the very next objective, locus, and tool/action you intend to execute.
        - Continuity: note the risks, invariants, or context that must carry forward.

        After </ide_reasoning>, write one concise user-facing sentence covering the Done → Next → Path arc. If tools are available, transition directly into the necessary tool calls; if tools are unavailable, state the blocker explicitly.
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
