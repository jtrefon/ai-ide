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
    
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?) async throws -> AIServiceResponse {
        try await performChat(prompt: message, context: context, tools: tools, mode: mode, projectRoot: nil)
    }
    
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
        try await performChat(prompt: message, context: context, tools: tools, mode: mode, projectRoot: projectRoot)
    }
    
    func sendMessage(_ messages: [ChatMessage], context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
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
                    return OpenRouterChatMessage(role: "assistant", content: msg.content.isEmpty ? nil : msg.content, tool_calls: toolCalls)
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
                    return OpenRouterChatMessage(role: "tool", content: content, tool_call_id: toolCallId)
                } else {
                    // Fallback if ID missing (shouldn't happen with new logic)
                    let content = Self.truncate(msg.content, limit: Self.maxToolOutputCharsForModel)
                    return OpenRouterChatMessage(role: "user", content: "Tool Output: \(content)")
                }
            }
        }
        
        return try await performChatWithHistory(messages: openRouterMessages, context: context, tools: tools, mode: mode, projectRoot: projectRoot)
    }

    private static func sanitizeToolCallOrdering(_ messages: [ChatMessage]) -> [ChatMessage] {
        let sanitizer = ToolCallOrderingSanitizer()
        return sanitizer.sanitize(messages)
    }
    
    func explainCode(_ code: String) async throws -> String {
        let prompt = "Explain the following code in clear, concise terms:\n\n\(code)"
        let response = try await performChat(prompt: prompt, context: nil, tools: nil, mode: nil, projectRoot: nil)
        return response.content ?? ""
    }
    
    func refactorCode(_ code: String, instructions: String) async throws -> String {
        let prompt = "Refactor this code using the following instructions:\n\(instructions)\n\nCode:\n\(code)"
        let response = try await performChat(prompt: prompt, context: nil, tools: nil, mode: nil, projectRoot: nil)
        return response.content ?? ""
    }
    
    func generateCode(_ prompt: String) async throws -> String {
        let message = "Generate code for the following request:\n\(prompt)"
        let response = try await performChat(prompt: message, context: nil, tools: nil, mode: nil, projectRoot: nil)
        return response.content ?? ""
    }
    
    func fixCode(_ code: String, error: String) async throws -> String {
        let prompt = "Fix this code. Error message:\n\(error)\n\nCode:\n\(code)"
        let response = try await performChat(prompt: prompt, context: nil, tools: nil, mode: nil, projectRoot: nil)
        return response.content ?? ""
    }
    
    private func performChat(prompt: String, context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
        return try await performChatWithHistory(
            messages: [OpenRouterChatMessage(role: "user", content: prompt)],
            context: context,
            tools: tools,
            mode: mode,
            projectRoot: projectRoot
        )
    }

    private func performChatWithHistory(messages: [OpenRouterChatMessage], context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
        let requestId = UUID().uuidString
        let settings = settingsStore.load()
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        try validateSettings(apiKey: apiKey, model: model)

        let systemContent = buildSystemContent(
            systemPrompt: systemPrompt,
            tools: tools,
            mode: mode,
            projectRoot: projectRoot,
            settings: settings
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

    private func buildSystemContent(
        systemPrompt: String,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?,
        settings: OpenRouterSettings
    ) -> String {
        var systemContent = systemPrompt.isEmpty
            ? (tools != nil ? ToolAwarenessPrompt.systemPrompt : "You are a helpful, concise coding assistant.")
            : systemPrompt

        if let mode = mode {
            systemContent += mode.systemPromptAddition
        }

        if let projectRoot = projectRoot {
            systemContent += "\n\n**IMPORTANT CONTEXT:**\nProject Root: `\(projectRoot.path)`\nPlatform: macOS\nAll file paths must be relative to the project root or validated absolute paths within it. Never use Linux-style paths like /home."
        }

        if settings.reasoningEnabled, mode != nil {
            systemContent += "\n\n## Reasoning\nWhen responding, include a structured reasoning block enclosed in <ide_reasoning>...</ide_reasoning>. This block will be shown in a separate, foldable UI panel.\n\nRequirements:\n- ALWAYS include all four sections in this exact order: Analyze, Research, Plan, Reflect.\n- If a section is not applicable, write 'N/A' (do not omit the section).\n- Keep it concise and actionable; use short bullets or short sentences.\n- Do NOT include code blocks in <ide_reasoning>.\n- Do NOT use placeholders like '...' or copy the format example text verbatim.\n- After </ide_reasoning>, provide the normal user-facing answer as usual (markdown allowed).\n\nFormat example:\n<ide_reasoning>\nAnalyze: - ... (write real bullets)\nResearch: - ... (write real bullets)\nPlan: - ... (write real bullets)\nReflect: - ... (write real bullets)\n</ide_reasoning>"
        }

        return systemContent
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
            return try await client.chatCompletion(
                apiKey: apiKey,
                baseURL: baseURL,
                appName: "OSX IDE",
                referer: "",
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
}

private struct OpenRouterChatRequest: Encodable {
    let model: String
    let messages: [OpenRouterChatMessage]
    let maxTokens: Int
    let temperature: Double
    let tools: [[String: Any]]?
    let toolChoice: String?
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case tools
        case toolChoice = "tool_choice"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(temperature, forKey: .temperature)
        if let tools = tools {
            // Need to wrap nested dictionaries for encoding since [String: Any] is not Encodable
            let data = try JSONSerialization.data(withJSONObject: tools)
            let json = try JSONSerialization.jsonObject(with: data)
            try container.encode(AnyCodable(json), forKey: .tools)
        }

        if let toolChoice, !toolChoice.isEmpty {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
    }
}

// Helper for encoding heterogeneous types
struct AnyCodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let val = value as? String { try container.encode(val) }
        else if let val = value as? Int { try container.encode(val) }
        else if let val = value as? Double { try container.encode(val) }
        else if let val = value as? Bool { try container.encode(val) }
        else if let val = value as? [String: Any] {
            var mapContainer = encoder.container(keyedBy: DynamicKey.self)
            for (key, v) in val {
                try mapContainer.encode(AnyCodable(v), forKey: DynamicKey(stringValue: key)!)
            }
        }
        else if let val = value as? [Any] {
            var arrContainer = encoder.unkeyedContainer()
            for v in val { try arrContainer.encode(AnyCodable(v)) }
        }
    }
    
    struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

private struct OpenRouterChatMessage: Encodable {
    let role: String
    let content: String?
    let tool_call_id: String?
    let tool_calls: [AIToolCall]?
    
    // Custom coding keys to handle optional encoding cleaner (although default works too if nil)
    // But content is required by some APIs unless it's a tool call assistant msg.
    // For now, let's keep it simple.
    
    init(role: String, content: String? = nil, tool_call_id: String? = nil, tool_calls: [AIToolCall]? = nil) {
        self.role = role
        self.content = content
        self.tool_call_id = tool_call_id
        self.tool_calls = tool_calls
    }
}

private struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let toolCalls: [AIToolCall]?
            
            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let message: Message
    }
    let choices: [Choice]
}
