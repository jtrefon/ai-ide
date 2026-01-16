//
//  OpenRouterAIService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation

actor OpenRouterAIService: AIService {
    private let settingsStore: OpenRouterSettingsStore
    private let client: OpenRouterAPIClient

    private static let maxToolOutputCharsForModel = 12_000

    init(
        settingsStore: OpenRouterSettingsStore = OpenRouterSettingsStore(),
        client: OpenRouterAPIClient = OpenRouterAPIClient()
    ) {
        self.settingsStore = settingsStore
        self.client = client
    }

    func sendMessage(
        _ message: String,
        context: String?,
        tools: [AITool]?,
        mode: AIMode?
    ) async throws -> AIServiceResponse {
        try await performChat(
            prompt: message,
            context: context,
            tools: tools,
            mode: mode,
            projectRoot: nil
        )
    }

    func sendMessage(
        _ message: String,
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async throws -> AIServiceResponse {
        try await performChat(
            prompt: message,
            context: context,
            tools: tools,
            mode: mode,
            projectRoot: projectRoot
        )
    }

    func sendMessage(
        _ messages: [ChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async throws -> AIServiceResponse {
        let sanitizedMessages = Self.sanitizeToolCallOrdering(messages)

        let validToolCallIds: Set<String> = Set(
            sanitizedMessages
                .compactMap { $0.toolCalls }
                .flatMap { $0 }
                .map { $0.id }
        )

        // Convert [ChatMessage] to [OpenRouterChatMessage]
        let openRouterMessages = sanitizedMessages.compactMap { msg -> OpenRouterChatMessage? in
            switch msg.role {
            case .user:
                return OpenRouterChatMessage(role: "user", content: msg.content)
            case .assistant:
                if let toolCalls = msg.toolCalls {
                    // Map tool calls
                    return OpenRouterChatMessage(
                        role: "assistant",
                        content: msg.content.isEmpty ? nil : msg.content,
                        toolCalls: toolCalls
                    )
                }
                return OpenRouterChatMessage(role: "assistant", content: msg.content)
            case .system:
                return OpenRouterChatMessage(role: "system", content: msg.content)
            case .tool:
                if msg.toolStatus == .executing {
                    return nil
                }
                // For tool outputs
                if let toolCallId = msg.toolCallId {
                    guard validToolCallIds.contains(toolCallId) else {
                        return nil
                    }
                    let content = Self.truncate(msg.content, limit: Self.maxToolOutputCharsForModel)
                    return OpenRouterChatMessage(role: "tool", content: content, toolCallID: toolCallId)
                } else {
                    // Fallback if ID missing (shouldn't happen with new logic)
                    let content = Self.truncate(msg.content, limit: Self.maxToolOutputCharsForModel)
                    return OpenRouterChatMessage(role: "user", content: "Tool Output: \(content)")
                }
            }
        }

        return try await performChatWithHistory(
            messages: openRouterMessages,
            context: context,
            tools: tools,
            mode: mode,
            projectRoot: projectRoot
        )
    }

    private static func sanitizeToolCallOrdering(_ messages: [ChatMessage]) -> [ChatMessage] {
        let sanitizer = ToolCallOrderingSanitizer()
        return sanitizer.sanitize(messages)
    }

    internal func performChat(
        prompt: String,
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async throws -> AIServiceResponse {
        return try await performChatWithHistory(
            messages: [OpenRouterChatMessage(role: "user", content: prompt)],
            context: context,
            tools: tools,
            mode: mode,
            projectRoot: projectRoot
        )
    }

    private func performChatWithHistory(
        messages: [OpenRouterChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async throws -> AIServiceResponse {
        let requestId = UUID().uuidString
        let settings = settingsStore.load()
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        try validateSettings(apiKey: apiKey, model: model)

        let systemContent = buildSystemContent(
            input: BuildSystemContentInput(
                systemPrompt: systemPrompt,
                hasTools: tools != nil,
                mode: mode,
                projectRoot: projectRoot,
                reasoningEnabled: settings.reasoningEnabled
            )
        )

        let finalMessages = buildFinalMessages(
            systemContent: systemContent,
            context: context,
            messages: messages
        )

        let toolDefinitions = buildToolDefinitions(tools: tools)
        let toolChoice = toolDefinitions?.isEmpty == false ? "auto" : nil

        await logRequestStart(
            requestId: requestId,
            model: model,
            messageCount: finalMessages.count,
            toolCount: toolDefinitions?.count ?? 0,
            mode: mode,
            projectRoot: projectRoot
        )

        let request = OpenRouterChatRequest(
            model: model,
            messages: finalMessages,
            maxTokens: 2048,
            temperature: 0.2,
            tools: toolDefinitions,
            toolChoice: toolChoice
        )

        let body = try JSONEncoder().encode(request)
        await logRequestBody(requestId: requestId, bytes: body.count)

        let data = try await executeChatCompletion(
            apiKey: apiKey,
            baseURL: settings.baseURL,
            body: body,
            requestId: requestId
        )

        let response = try await decodeResponse(data: data, requestId: requestId)
        guard let choice = response.choices.first else {
            throw AppError.aiServiceError("OpenRouter response was empty.")
        }

        await logRequestSuccess(
            requestId: requestId,
            contentLength: choice.message.content?.count ?? 0,
            toolCalls: choice.message.toolCalls?.count ?? 0,
            responseBytes: data.count
        )

        return AIServiceResponse(
            content: choice.message.content,
            toolCalls: choice.message.toolCalls
        )
    }

    // MARK: - Helper Methods

    private func validateSettings(apiKey: String, model: String) throws {
        guard !apiKey.isEmpty else {
            throw AppError.aiServiceError("OpenRouter API key is missing.")
        }
        guard !model.isEmpty else {
            throw AppError.aiServiceError("OpenRouter model is not set.")
        }
    }

    private func buildFinalMessages(
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

    private func buildToolDefinitions(tools: [AITool]?) -> [[String: Any]]? {
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

    private func logRequestStart(
        requestId: String,
        model: String,
        messageCount: Int,
        toolCount: Int,
        mode: AIMode?,
        projectRoot: URL?
    ) async {
        await AppLogger.shared.info(category: .ai, message: "openrouter.request_start", metadata: [
            "requestId": requestId,
            "model": model,
            "messageCount": messageCount,
            "toolCount": toolCount,
            "mode": mode?.rawValue as Any,
            "projectRoot": projectRoot?.path as Any
        ])

        await AIToolTraceLogger.shared.log(type: "openrouter.request", data: [
            "model": model,
            "messages": messageCount,
            "tools": toolCount,
            "mode": mode?.rawValue as Any,
            "projectRoot": projectRoot?.path as Any
        ])
    }

    private func logRequestBody(requestId: String, bytes: Int) async {
        await AppLogger.shared.debug(category: .ai, message: "openrouter.request_body", metadata: [
            "requestId": requestId,
            "bytes": bytes
        ])

        await AIToolTraceLogger.shared.log(type: "openrouter.request_body", data: [
            "bytes": bytes
        ])
    }

    private func executeChatCompletion(
        apiKey: String,
        baseURL: String,
        body: Data,
        requestId: String
    ) async throws -> Data {
        do {
            let requestContext = OpenRouterAPIClient.RequestContext(
                baseURL: baseURL,
                appName: "OSX IDE",
                referer: ""
            )
            return try await client.chatCompletion(
                apiKey: apiKey,
                context: requestContext,
                body: body
            )
        } catch {
            if let openRouterError = error as? OpenRouterServiceError {
                if case let .serverError(code, body) = openRouterError {
                    let snippet = (body ?? "").prefix(2000)
                    await logRequestError(requestId: requestId, status: code, bodySnippet: String(snippet))
                }
            }
            throw error
        }
    }

    private func logRequestError(requestId: String, status: Int, bodySnippet: String) async {
        await AppLogger.shared.error(category: .ai, message: "openrouter.request_error", metadata: [
            "requestId": requestId,
            "status": status,
            "bodySnippet": bodySnippet
        ])

        await AIToolTraceLogger.shared.log(type: "openrouter.error", data: [
            "status": status,
            "bodySnippet": bodySnippet
        ])
    }

    private func decodeResponse(data: Data, requestId: String) async throws -> OpenRouterChatResponse {
        do {
            return try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        } catch {
            let bodySnippet = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            await AppLogger.shared.error(category: .ai, message: "openrouter.decode_error", metadata: [
                "requestId": requestId,
                "error": error.localizedDescription,
                "bodySnippet": bodySnippet
            ])
            throw error
        }
    }

    private func logRequestSuccess(
        requestId: String,
        contentLength: Int,
        toolCalls: Int,
        responseBytes: Int
    ) async {
        await AppLogger.shared.info(category: .ai, message: "openrouter.request_success", metadata: [
            "requestId": requestId,
            "contentLength": contentLength,
            "toolCalls": toolCalls,
            "responseBytes": responseBytes
        ])

        await AIToolTraceLogger.shared.log(type: "openrouter.response", data: [
            "contentLength": contentLength,
            "toolCalls": toolCalls
        ])
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }

    private struct BuildSystemContentInput {
        let systemPrompt: String
        let hasTools: Bool
        let mode: AIMode?
        let projectRoot: URL?
        let reasoningEnabled: Bool
    }

    private func buildSystemContent(input: BuildSystemContentInput) -> String {
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

    private func buildBaseSystemContent(systemPrompt: String, hasTools: Bool) -> String {
        if !systemPrompt.isEmpty {
            return systemPrompt
        }

        if hasTools {
            return ToolAwarenessPrompt.systemPrompt
        }

        return "You are a helpful, concise coding assistant."
    }

    private func buildModeSystemAddition(mode: AIMode?) -> String? {
        guard let mode else { return nil }
        return mode.systemPromptAddition
    }

    private func buildProjectRootContext(projectRoot: URL?) -> String? {
        guard let projectRoot else { return nil }
        return """

        **IMPORTANT CONTEXT:**
        Project Root: `\(projectRoot.path)`
        Platform: macOS
        All file paths must be relative to the project root or validated absolute paths within it.
        Never use Linux-style paths like /home.
        """
    }

    private func buildReasoningPromptIfNeeded(reasoningEnabled: Bool, mode: AIMode?) -> String? {
        guard reasoningEnabled, mode != nil else { return nil }
        return """

        ## Reasoning
        When responding, include a structured reasoning block enclosed in <ide_reasoning>...</ide_reasoning>.
        This block will be shown in a separate, foldable UI panel.

        Requirements:
        - ALWAYS include all four sections in this exact order: Analyze, Research, Plan, Reflect.
        - If a section is not applicable, write 'N/A' (do not omit the section).
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
        </ide_reasoning>
        """
    }
}
