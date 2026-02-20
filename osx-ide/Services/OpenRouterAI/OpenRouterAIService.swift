import Foundation

actor OpenRouterAIService: AIService {
    internal let settingsStore: OpenRouterSettingsStore
    internal let client: OpenRouterAPIClient
    private let eventBus: EventBusProtocol
    private var contextLengthByModelId: [String: Int] = [:]

    internal static let maxToolOutputCharsForModel = 12_000

    init(
        settingsStore: OpenRouterSettingsStore = OpenRouterSettingsStore(),
        client: OpenRouterAPIClient = OpenRouterAPIClient(),
        eventBus: EventBusProtocol
    ) {
        self.settingsStore = settingsStore
        self.client = client
        self.eventBus = eventBus
    }

    /// Send a message with streaming support
    func sendMessageStreaming(
        _ request: AIServiceHistoryRequest,
        runId: String
    ) async throws -> AIServiceResponse {
        let openRouterMessages = buildOpenRouterMessages(from: request.messages)
        let historyInput = buildHistoryInput(messages: openRouterMessages, from: request)
        return try await performChatStreamingWithHistory(historyInput, runId: runId)
    }

    private func performChatStreamingWithHistory(
        _ request: OpenRouterChatHistoryInput,
        runId: String
    ) async throws -> AIServiceResponse {
        let preparation = try buildChatPreparation(request: request)

        await logRequestStart(RequestStartContext(
            requestId: preparation.requestId,
            model: preparation.settings.model,
            messageCount: preparation.finalMessages.count,
            toolCount: preparation.toolDefinitions?.count ?? 0,
            mode: request.mode,
            projectRoot: request.projectRoot,
            runId: request.runId,
            stage: request.stage
        ))

        let requestBody = OpenRouterChatRequest(
            model: preparation.settings.model,
            messages: preparation.finalMessages,
            maxTokens: 2048,
            temperature: 0.2,
            tools: preparation.toolDefinitions,
            toolChoice: preparation.toolChoice,
            stream: true  // Enable streaming
        )

        let body = try JSONEncoder().encode(requestBody)
        await logRequestBody(requestId: preparation.requestId, bytes: body.count)

        // Collect streaming chunks using a thread-safe wrapper
        final class ChunkCollector: @unchecked Sendable {
            var chunks: [String] = []
            var toolCalls: [AIToolCall] = []
            let lock = NSLock()
            
            func appendChunk(_ content: String) {
                lock.lock()
                defer { lock.unlock() }
                chunks.append(content)
            }
            
            func appendToolCalls(_ calls: [AIToolCall]) {
                lock.lock()
                defer { lock.unlock() }
                toolCalls.append(contentsOf: calls)
            }
            
            func getResults() -> (content: String, toolCalls: [AIToolCall]?) {
                lock.lock()
                defer { lock.unlock() }
                let content = chunks.joined()
                let tc = toolCalls.isEmpty ? nil : toolCalls
                return (content, tc)
            }
        }
        
        let collector = ChunkCollector()

        let requestContext = OpenRouterAPIClient.RequestContext(
            baseURL: preparation.settings.baseURL,
            appName: "OSX IDE",
            referer: ""
        )

        try await client.chatCompletionStreaming(
            apiKey: preparation.settings.apiKey,
            context: requestContext,
            body: body
        ) { [weak self] chunkJson in
            guard let self = self else { return }

            // Parse the chunk
            if let chunkData = chunkJson.data(using: .utf8),
               let chunk = try? JSONDecoder().decode(OpenRouterChatResponseChunk.self, from: chunkData) {
                if let delta = chunk.choices.first?.delta {
                    if let content = delta.content {
                        collector.appendChunk(content)
                        // Publish streaming chunk event
                        Task { @MainActor in
                            self.eventBus.publish(LocalModelStreamingChunkEvent(
                                runId: runId,
                                chunk: content
                            ))
                        }
                    }
                    if let newToolCalls = delta.toolCalls, !newToolCalls.isEmpty {
                        collector.appendToolCalls(newToolCalls)
                    }
                }
            }
        }

        // Get collected results
        let results = collector.getResults()
        let fullContent = results.content
        let toolCalls = results.toolCalls

        // Log success
        await logRequestSuccess(
            requestId: preparation.requestId,
            contentLength: fullContent.count,
            toolCalls: toolCalls?.count ?? 0,
            responseBytes: 0
        )

        return AIServiceResponse(
            content: fullContent,
            toolCalls: toolCalls
        )
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
            projectRoot: request.projectRoot,
            runId: request.runId,
            stage: request.stage
        )
    }

    private func performChat(
        _ request: OpenRouterChatInput
    ) async throws -> AIServiceResponse {
        return try await performChatWithHistory(OpenRouterChatHistoryInput(
            messages: [OpenRouterChatMessage(role: "user", content: request.prompt)],
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            projectRoot: request.projectRoot,
            runId: nil,
            stage: nil
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
            projectRoot: request.projectRoot,
            runId: request.runId,
            stage: request.stage
        ))

        let requestBody = OpenRouterChatRequest(
            model: preparation.settings.model,
            messages: preparation.finalMessages,
            maxTokens: 2048,
            temperature: 0.2,
            tools: preparation.toolDefinitions,
            toolChoice: preparation.toolChoice,
            stream: false
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

        if let usage = response.usage,
           let promptTokens = usage.promptTokens,
           let completionTokens = usage.completionTokens,
           let totalTokens = usage.totalTokens {
            let contextLength = try? await fetchContextLength(
                modelId: preparation.settings.model,
                apiKey: preparation.settings.apiKey,
                baseURL: preparation.settings.baseURL
            )
            let event = OpenRouterUsageUpdatedEvent(
                modelId: preparation.settings.model,
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

    private func fetchContextLength(modelId: String, apiKey: String, baseURL: String) async throws -> Int? {
        if let cached = contextLengthByModelId[modelId] {
            return cached
        }
        let requestContext = OpenRouterAPIClient.RequestContext(
            baseURL: baseURL,
            appName: "OSX IDE",
            referer: ""
        )
        let models = try await client.fetchModels(apiKey: apiKey, context: requestContext)
        guard let model = models.first(where: { $0.id == modelId }) else {
            return nil
        }
        if let contextLength = model.contextLength {
            contextLengthByModelId[modelId] = contextLength
        }
        return model.contextLength
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

    private func decodeResponse(data: Data, requestId: String) async throws -> OpenRouterChatResponse {
        do {
            return try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        } catch {
            if let openRouterErrorMessage = decodeOpenRouterErrorMessage(from: data) {
                await AppLogger.shared.error(
                    category: .ai,
                    message: "openrouter.response_error",
                    context: AppLogger.LogCallContext(metadata: [
                        "requestId": requestId,
                        "error": openRouterErrorMessage
                    ])
                )
                throw AppError.aiServiceError(openRouterErrorMessage)
            }

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
            throw AppError.aiServiceError("Failed to decode OpenRouter response: \(error.localizedDescription)")
        }
    }

    private func decodeOpenRouterErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct ErrorBody: Decodable {
                struct Metadata: Decodable {
                    let raw: String?
                    let providerName: String?
                    let isByok: Bool?

                    private enum CodingKeys: String, CodingKey {
                        case raw
                        case providerName = "provider_name"
                        case isByok = "is_byok"
                    }
                }

                let message: String?
                let code: Int?
                let metadata: Metadata?
            }

            let error: ErrorBody?
        }

        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
              let err = envelope.error else {
            return nil
        }

        let providerName = err.metadata?.providerName
        let providerSuffix = providerName?.isEmpty == false ? " Provider: \(providerName!)." : ""
        if let code = err.code, let message = err.message, !message.isEmpty {
            return "OpenRouter error (\(code)): \(message).\(providerSuffix)"
        }
        if let message = err.message, !message.isEmpty {
            return "OpenRouter error: \(message).\(providerSuffix)"
        }
        return nil
    }
}
