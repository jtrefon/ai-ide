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
        _ request: AIServiceMessageWithProjectRootRequest
    ) async throws -> AIServiceResponse {
        try await performChat(OpenRouterChatInput(
            prompt: request.message,
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            projectRoot: request.projectRoot
        ))
    }

    func sendMessage(
        _ request: AIServiceHistoryRequest
    ) async throws -> AIServiceResponse {
        let openRouterMessages = buildOpenRouterMessages(from: request.messages)
        let historyInput = buildHistoryInput(messages: openRouterMessages, from: request)
        return try await performChatWithHistory(historyInput)
    }

    private func buildHistoryInput(messages: [OpenRouterChatMessage], from request: AIServiceHistoryRequest) -> OpenRouterChatHistoryInput {
        OpenRouterChatHistoryInput(
            messages: messages,
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            projectRoot: request.projectRoot
        )
    }

    private static func sanitizeToolCallOrdering(_ messages: [ChatMessage]) -> [ChatMessage] {
        let sanitizer = ToolCallOrderingSanitizer()
        return sanitizer.sanitize(messages)
    }

    private func buildOpenRouterMessages(from messages: [ChatMessage]) -> [OpenRouterChatMessage] {
        let sanitizedMessages = Self.sanitizeToolCallOrdering(messages)
        let validToolCallIds = buildValidToolCallIds(from: sanitizedMessages)
        return sanitizedMessages.compactMap { message in
            mapOpenRouterChatMessage(message, validToolCallIds: validToolCallIds)
        }
    }

    private func buildValidToolCallIds(from messages: [ChatMessage]) -> Set<String> {
        Set(
            messages
                .compactMap { $0.toolCalls }
                .flatMap { $0 }
                .map { $0.id }
        )
    }

    private func mapOpenRouterChatMessage(
        _ message: ChatMessage,
        validToolCallIds: Set<String>
    ) -> OpenRouterChatMessage? {
        switch message.role {
        case .user:
            return OpenRouterChatMessage(role: "user", content: message.content)
        case .assistant:
            if let toolCalls = message.toolCalls {
                return OpenRouterChatMessage(
                    role: "assistant",
                    content: message.content.isEmpty ? nil : message.content,
                    toolCalls: toolCalls
                )
            }
            return OpenRouterChatMessage(role: "assistant", content: message.content)
        case .system:
            return OpenRouterChatMessage(role: "system", content: message.content)
        case .tool:
            return mapToolMessage(message, validToolCallIds: validToolCallIds)
        }
    }

    private func mapToolMessage(
        _ message: ChatMessage,
        validToolCallIds: Set<String>
    ) -> OpenRouterChatMessage? {
        guard message.toolStatus != .executing else { return nil }
        if let toolCallId = message.toolCallId {
            return mapValidToolMessage(message, toolCallId: toolCallId, validToolCallIds: validToolCallIds)
        }
        return mapFallbackToolMessage(message)
    }

    private func mapValidToolMessage(_ message: ChatMessage, toolCallId: String, validToolCallIds: Set<String>) -> OpenRouterChatMessage? {
        guard validToolCallIds.contains(toolCallId) else { return nil }
        let content = Self.truncate(message.content, limit: Self.maxToolOutputCharsForModel)
        return OpenRouterChatMessage(role: "tool", content: content, toolCallID: toolCallId)
    }

    private func mapFallbackToolMessage(_ message: ChatMessage) -> OpenRouterChatMessage {
        let content = Self.truncate(message.content, limit: Self.maxToolOutputCharsForModel)
        return OpenRouterChatMessage(role: "user", content: "Tool Output: \(content)")
    }

    private func performChat(
        _ request: OpenRouterChatInput
    ) async throws -> AIServiceResponse {
        return try await performChatWithHistory(OpenRouterChatHistoryInput(
            messages: [OpenRouterChatMessage(role: "user", content: request.prompt)],
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            projectRoot: request.projectRoot
        ))
    }

    private func performChatWithHistory(
        _ request: OpenRouterChatHistoryInput
    ) async throws -> AIServiceResponse {
        let preparation = try buildChatPreparation(request: request)

        await logRequestStart(RequestStartContext(
            requestId: preparation.requestId,
            model: preparation.settings.model,
            messageCount: preparation.finalMessages.count,
            toolCount: preparation.toolDefinitions?.count ?? 0,
            mode: request.mode,
            projectRoot: request.projectRoot
        ))

        let requestBody = OpenRouterChatRequest(
            model: preparation.settings.model,
            messages: preparation.finalMessages,
            maxTokens: 2048,
            temperature: 0.2,
            tools: preparation.toolDefinitions,
            toolChoice: preparation.toolChoice
        )

        let body = try JSONEncoder().encode(requestBody)
        await logRequestBody(requestId: preparation.requestId, bytes: body.count)

        let data = try await executeChatCompletion(
            apiKey: preparation.settings.apiKey,
            baseURL: preparation.settings.baseURL,
            body: body,
            requestId: preparation.requestId
        )

        let response = try await decodeResponse(data: data, requestId: preparation.requestId)
        guard let choice = response.choices.first else {
            throw AppError.aiServiceError("OpenRouter response was empty.")
        }

        await logRequestSuccess(
            requestId: preparation.requestId,
            contentLength: choice.message.content?.count ?? 0,
            toolCalls: choice.message.toolCalls?.count ?? 0,
            responseBytes: data.count
        )

        let resolvedToolCalls = request.tools?.isEmpty == false
            ? choice.message.toolCalls
            : nil

        return AIServiceResponse(
            content: choice.message.content,
            toolCalls: resolvedToolCalls
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
        _ context: RequestStartContext
    ) async {
        await AppLogger.shared.info(
            category: .ai,
            message: "openrouter.request_start",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": context.requestId,
                "model": context.model,
                "messageCount": context.messageCount,
                "toolCount": context.toolCount,
                "mode": context.mode?.rawValue as Any,
                "projectRoot": context.projectRoot?.path as Any
            ])
        )

        await AIToolTraceLogger.shared.log(type: "openrouter.request", data: [
            "model": context.model,
            "messages": context.messageCount,
            "tools": context.toolCount,
            "mode": context.mode?.rawValue as Any,
            "projectRoot": context.projectRoot?.path as Any
        ])
    }

    private func logRequestBody(requestId: String, bytes: Int) async {
        await AppLogger.shared.debug(
            category: .ai,
            message: "openrouter.request_body",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": requestId,
                "bytes": bytes
            ])
        )

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
        await AppLogger.shared.error(
            category: .ai,
            message: "openrouter.request_error",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": requestId,
                "status": status,
                "bodySnippet": bodySnippet
            ])
        )

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
            await AppLogger.shared.error(
                category: .ai,
                message: "openrouter.decode_error",
                context: AppLogger.LogCallContext(metadata: [
                    "requestId": requestId,
                    "error": error.localizedDescription,
                    "bodySnippet": bodySnippet
                ])
            )
            throw error
        }
    }

    private func logRequestSuccess(
        requestId: String,
        contentLength: Int,
        toolCalls: Int,
        responseBytes: Int
    ) async {
        await AppLogger.shared.info(
            category: .ai,
            message: "openrouter.request_success",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": requestId,
                "contentLength": contentLength,
                "toolCalls": toolCalls,
                "responseBytes": responseBytes
            ])
        )

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

    private struct OpenRouterChatInput {
        let prompt: String
        let context: String?
        let tools: [AITool]?
        let mode: AIMode?
        let projectRoot: URL?
    }

    private struct OpenRouterChatHistoryInput {
        let messages: [OpenRouterChatMessage]
        let context: String?
        let tools: [AITool]?
        let mode: AIMode?
        let projectRoot: URL?
    }

    private struct RequestStartContext {
        let requestId: String
        let model: String
        let messageCount: Int
        let toolCount: Int
        let mode: AIMode?
        let projectRoot: URL?
    }

    private struct SettingsSnapshot {
        let apiKey: String
        let model: String
        let systemPrompt: String
        let baseURL: String
        let reasoningEnabled: Bool
    }

    private struct ChatPreparation {
        let requestId: String
        let settings: SettingsSnapshot
        let finalMessages: [OpenRouterChatMessage]
        let toolDefinitions: [[String: Any]]?
        let toolChoice: String?
    }

    private func buildChatPreparation(
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

    private func loadSettingsSnapshot() -> SettingsSnapshot {
        let settings = settingsStore.load()
        return SettingsSnapshot(
            apiKey: settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: settings.baseURL,
            reasoningEnabled: settings.reasoningEnabled
        )
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
}
