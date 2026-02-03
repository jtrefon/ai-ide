import Foundation

#if canImport(MLX)
import MLX
#endif

#if canImport(MLXLMCommon)
import MLXLMCommon
#endif

#if canImport(MLXLLM)
import MLXLLM
#endif

actor LocalMLXAIService: AIServiceStreaming {
    private let settingsStore: LocalModelSettingsStore
    private let fileStore: LocalModelFileStore
    private let eventBus: EventBusProtocol?

    init(
        settingsStore: LocalModelSettingsStore = LocalModelSettingsStore(),
        eventBus: EventBusProtocol? = nil
    ) {
        self.settingsStore = settingsStore
        self.fileStore = LocalModelFileStore()
        self.eventBus = eventBus
    }

    private static func isSoftStopBoundary(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last == "\n" || last == "." || last == "!" || last == "?"
    }

    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
        try await handle(
            messages: [ChatMessage(role: .user, content: request.message)],
            context: request.context,
            tools: request.tools,
            mode: request.mode
        )
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        return try await handle(
            messages: request.messages,
            context: request.context,
            tools: request.tools,
            mode: request.mode
        )
    }

    func sendMessageStream(
        _ request: AIServiceHistoryRequest,
        onChunk: @MainActor @Sendable @escaping (String) -> Void
    ) async throws -> AIServiceResponse {
        return try await handle(
            messages: request.messages,
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            onChunk: onChunk
        )
    }

    func explainCode(_ code: String) async throws -> String {
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: "Explain the following code:\n\n\(code)",
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: "Refactor using instructions: \(instructions)\n\nCode:\n\(code)",
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func generateCode(_ prompt: String) async throws -> String {
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: "Generate code for: \(prompt)",
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: "Fix this code. Error: \(error)\n\nCode:\n\(code)",
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    private func handle(
        messages: [ChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        onChunk: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> AIServiceResponse {
        let settings = settingsStore.load()
        guard settings.isEnabled else {
            throw AppError.aiServiceError("Local model is disabled. Enable it in Settings > AI.")
        }

        let toolList = tools ?? []
        if !toolList.isEmpty {
            let toolAwarePrompt = buildToolAwarePrompt(messages: messages, context: context, tools: toolList)
            return try await generateAndParseResponse(
                promptText: toolAwarePrompt,
                contextTextForUsage: context,
                settings: settings,
                onChunk: onChunk
            )
        }

        // Tool-free path can stream.
        let promptText = buildChatPrompt(messages: messages, context: context, mode: mode)
        return try await generateAndParseResponse(
            promptText: promptText,
            contextTextForUsage: context,
            settings: settings,
            onChunk: onChunk
        )
    }

    private func generateAndParseResponse(
        promptText: String,
        contextTextForUsage: String?,
        settings: LocalModelSettings,
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> AIServiceResponse {
        #if canImport(MLXLMCommon) && canImport(MLXLLM)
        let usagePromptText = combinePrompt(prompt: promptText, context: contextTextForUsage)
        let trimmedPromptText = trimPromptIfNeeded(
            usagePromptText,
            maxTokens: settings.contextBudgetTokens
        )

        let rawOutput = try await generateResponse(
            promptText: trimmedPromptText,
            modelId: settings.selectedModelId,
            quantization: settings.quantization,
            maxAnswerTokens: settings.maxAnswerTokens,
            maxReasoningTokens: settings.maxReasoningTokens,
            temperature: settings.temperature,
            onChunk: onChunk
        )
        await publishUsageIfPossible(
            modelId: settings.selectedModelId,
            promptText: trimmedPromptText,
            completionText: rawOutput
        )
        #else
        let rawOutput = "Local model runtime is not available in this build. Ensure the MLX Swift LM package (MLXLLM) is linked."
        #endif

        if let toolCalls = LocalToolCallAdapter.parseToolCallsIfPresent(from: rawOutput) {
            return AIServiceResponse(content: nil, toolCalls: toolCalls)
        }

        return AIServiceResponse(content: rawOutput, toolCalls: nil)
    }

    private func combinePrompt(prompt: String, context: String?) -> String {
        if let context, !context.isEmpty {
            return "Context:\n\(context)\n\nUser:\n\(prompt)"
        }
        return prompt
    }

    private func trimPromptIfNeeded(_ prompt: String, maxTokens: Int) -> String {
        guard maxTokens > 0 else { return "" }
        let tokens = prompt
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)

        guard tokens.count > maxTokens else { return prompt }

        // Sliding window: keep the most recent tokens to stay within budget.
        let trimmed = tokens.suffix(maxTokens).joined(separator: " ")
        return trimmed
    }

    private func buildChatPrompt(messages: [ChatMessage], context: String?, mode: AIMode?) -> String {
        var lines: [String] = []
        lines.append("You are an AI coding assistant.")
        let settings = settingsStore.load()
        lines.append("Token budgets (target): reasoning <= \(settings.maxReasoningTokens) tokens, final answer <= \(settings.maxAnswerTokens) tokens.")
        lines.append("Plan your response to fit within these budgets. If nearing the limit, summarize and conclude cleanly.")
        if mode == .agent {
            lines.append("You are in Agent mode. If tools are available they will be provided separately.")
            if shouldForceReasoningInAgentMode(messages: messages) {
                lines.append(fullReasoningInstruction())
            } else {
                lines.append(conciseReasoningInstruction())
            }
        }

        lines.append("Conversation:")
        for message in messages {
            switch message.role {
            case .system:
                lines.append("SYSTEM: \(message.content)")
            case .user:
                lines.append("USER: \(message.content)")
            case .assistant:
                lines.append("ASSISTANT: \(message.content)")
            case .tool:
                lines.append("TOOL: \(toolPromptText(for: message))")
            }
        }

        lines.append("ASSISTANT:")
        return lines.joined(separator: "\n")
    }

    private func shouldForceReasoningInAgentMode(messages: [ChatMessage]) -> Bool {
        guard OpenRouterSettingsStore().load(includeApiKey: false).reasoningEnabled else { return false }
        let hasAnyReasoningAlready = messages.contains { message in
            message.role == .assistant && message.content.contains("<ide_reasoning>")
        }
        return !hasAnyReasoningAlready
    }

    private func fullReasoningInstruction() -> String {
        "When responding, you MUST include a structured reasoning block enclosed in <ide_reasoning>...</ide_reasoning> with ALL six sections: Analyze, Research, Plan, Reflect, Action, Delivery. Keep it reasonably detailed for the initial agent response. After </ide_reasoning>, provide the normal user-visible answer."
    }

    private func conciseReasoningInstruction() -> String {
        "For follow-up agent steps, include <ide_reasoning>...</ide_reasoning> with ALL six sections (Analyze, Research, Plan, Reflect, Action, Delivery) but keep it concise (short bullets). After </ide_reasoning>, provide the user-visible response or the next tool call JSON as required."
    }

    private func toolPromptText(for message: ChatMessage) -> String {
        let raw = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "(empty)" }
        if let envelope = ToolExecutionEnvelope.decode(from: raw) {
            let payloadPreview = envelope.payload?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let payloadPreview, !payloadPreview.isEmpty {
                return truncateToolPromptText(payloadPreview)
            }
            return truncateToolPromptText(envelope.message)
        }
        return truncateToolPromptText(raw)
    }

    private func truncateToolPromptText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 800 { return trimmed }
        return String(trimmed.prefix(800)) + "\n[TRUNCATED]"
    }

    private func buildToolAwarePrompt(messages: [ChatMessage], context: String?, tools: [AITool]) -> String {
        var lines: [String] = []
        lines.append("You are an AI coding assistant running in an IDE with tool access.")
        let settings = settingsStore.load()
        lines.append("Token budgets (target): reasoning <= \(settings.maxReasoningTokens) tokens, final answer <= \(settings.maxAnswerTokens) tokens.")
        lines.append("Plan your response to fit within these budgets. If nearing the limit, summarize and conclude cleanly.")
        if shouldForceReasoningInAgentMode(messages: messages) {
            lines.append(fullReasoningInstruction())
        } else {
            lines.append(conciseReasoningInstruction())
        }
        lines.append("When you need to take an action, you MUST call tools instead of writing code blocks.")
        lines.append("If you call a tool, reply with ONLY a single JSON object in this exact format:")
        lines.append("{\"type\":\"tool_call\",\"calls\":[{\"id\":\"<id>\",\"name\":\"<tool_name>\",\"arguments\":{...}}]}")
        lines.append("Do not include any other keys. Do not include markdown. Do not include any prose.")
        lines.append("If no tool is needed, reply normally with user-visible text.")

        lines.append("Available tools (JSON Schema):")
        for tool in tools {
            let schemaData = (try? JSONSerialization.data(withJSONObject: tool.parameters, options: [.sortedKeys])) ?? Data()
            let schemaString = String(data: schemaData, encoding: .utf8) ?? "{}"
            lines.append("- \(tool.name): \(tool.description)")
            lines.append("  parameters: \(schemaString)")
        }

        lines.append("Conversation:")
        for message in messages {
            switch message.role {
            case .system:
                lines.append("SYSTEM: \(message.content)")
            case .user:
                lines.append("USER: \(message.content)")
            case .assistant:
                lines.append("ASSISTANT: \(message.content)")
            case .tool:
                lines.append("TOOL: \(toolPromptText(for: message))")
            }
        }

        lines.append("ASSISTANT:")
        return lines.joined(separator: "\n")
    }

    private func publishUsageIfPossible(modelId: String, promptText: String, completionText: String) async {
        guard let eventBus else { return }
        let promptTokens = Self.estimateTokenCount(promptText)
        let completionTokens = Self.estimateTokenCount(completionText)
        let totalTokens = promptTokens + completionTokens
        let contextLength = LocalModelCatalog.item(id: modelId)?.contextLength

        let event = OpenRouterUsageUpdatedEvent(
            modelId: modelId,
            usage: OpenRouterUsageUpdatedEvent.Usage(
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens
            ),
            contextLength: contextLength
        )
        await MainActor.run {
            eventBus.publish(event)
        }
    }

    private static func estimateTokenCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    #if canImport(MLXLMCommon) && canImport(MLXLLM)
    private func generateResponse(
        promptText: String,
        modelId: String,
        quantization: LocalModelQuantization,
        maxAnswerTokens: Int,
        maxReasoningTokens: Int,
        temperature: Double,
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        let modelFactory = LLMModelFactory.shared

        let modelDirectory = fileStore.modelDirectory(modelId: modelId, quantization: quantization)
        let configuration = ModelConfiguration(directory: modelDirectory)
        let container = try await modelFactory.loadContainer(configuration: configuration)

        return try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: promptText))

            let safeTemperature = Float(max(0.0, min(2.0, temperature)))
            let params = GenerateParameters(temperature: safeTemperature)
            let tokenStream = try MLXLMCommon.generate(input: input, parameters: params, context: context)
            var output = ""
            var answerTokenCount = 0
            var reasoningTokenCount = 0
            let targetAnswerTokens = max(1, maxAnswerTokens)
            let targetReasoningTokens = max(1, maxReasoningTokens)
            let runawaySafetyMaxTokens = max(256, (targetAnswerTokens + targetReasoningTokens) * 4)
            var totalTokenCount = 0
            var isInReasoning = false

            for await part in tokenStream {
                if let chunk = part.chunk {
                    output += chunk
                    isInReasoning = output.contains("<ide_reasoning>") && !output.contains("</ide_reasoning>")

                    let chunkTokens = Self.estimateTokenCount(chunk)
                    totalTokenCount += chunkTokens
                    if isInReasoning {
                        reasoningTokenCount += chunkTokens
                    } else {
                        answerTokenCount += chunkTokens
                    }

                    if let onChunk {
                        await onChunk(chunk)
                    }
                }

                if totalTokenCount >= runawaySafetyMaxTokens {
                    break
                }

                if !isInReasoning,
                   answerTokenCount >= targetAnswerTokens,
                   Self.isSoftStopBoundary(output) {
                    break
                }
            }

            return output
        }
    }
    #endif
}

enum LocalToolCallAdapter {
    static func parseToolCallsIfPresent(from text: String) -> [AIToolCall]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }

        struct Wrapper: Decodable {
            struct Call: Decodable {
                let id: String
                let name: String
                let arguments: [String: JSONValue]
            }
            let type: String
            let calls: [Call]
        }

        do {
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            guard wrapper.type == "tool_call" else { return nil }
            return wrapper.calls.map { call in
                let args = call.arguments.mapValues { $0.anyValue }
                return AIToolCall(id: call.id, name: call.name, arguments: args)
            }
        } catch {
            return nil
        }
    }
}

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues { $0.anyValue }
        case .array(let value): return value.map { $0.anyValue }
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}
