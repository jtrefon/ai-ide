import Foundation

actor OpenRouterProviderRateLimiter {
    struct WaitReservation {
        let waitTime: TimeInterval
        let isProviderCooldown: Bool
    }

    private var lastRequestTime: Date = Date.distantPast
    private var providerCooldownUntil: Date = Date.distantPast
    private var consecutiveRateLimitCount: Int = 0

    func reserveWait(minimumInterval: TimeInterval, now: Date = Date()) -> WaitReservation {
        let intervalReadyAt = lastRequestTime.addingTimeInterval(minimumInterval)
        let nextRequestTime = max(intervalReadyAt, providerCooldownUntil)
        let computedWait = max(0, nextRequestTime.timeIntervalSince(now))
        let isProviderCooldown = providerCooldownUntil > now && providerCooldownUntil >= intervalReadyAt

        if computedWait > 0 {
            lastRequestTime = nextRequestTime
            return WaitReservation(waitTime: computedWait, isProviderCooldown: isProviderCooldown)
        }

        lastRequestTime = now
        return WaitReservation(waitTime: 0, isProviderCooldown: false)
    }

    func registerRateLimit(statusCode: Int, now: Date = Date()) -> TimeInterval {
        consecutiveRateLimitCount += 1
        let cooldownDuration = cooldownDuration(
            forStatusCode: statusCode,
            consecutiveRateLimitCount: consecutiveRateLimitCount
        )
        let cooldownUntil = now.addingTimeInterval(cooldownDuration)

        if cooldownUntil > providerCooldownUntil {
            providerCooldownUntil = cooldownUntil
        }

        return cooldownDuration
    }

    func registerSuccess(now: Date = Date()) {
        consecutiveRateLimitCount = 0
        if providerCooldownUntil < now {
            providerCooldownUntil = .distantPast
        }
        lastRequestTime = max(lastRequestTime, now)
    }

    func cooldownDuration(
        forStatusCode statusCode: Int,
        consecutiveRateLimitCount: Int
    ) -> TimeInterval {
        let baseDuration: TimeInterval
        switch statusCode {
        case 429:
            baseDuration = 20
        case 421:
            baseDuration = 10
        default:
            baseDuration = 0
        }

        guard baseDuration > 0 else { return 0 }
        let escalationMultiplier = min(max(consecutiveRateLimitCount - 1, 0), 3)
        return baseDuration * Double(1 + escalationMultiplier)
    }
}

actor OpenRouterAIService: AIService, RemoteAIAccountStatusRefreshing {
    internal let settingsStore: any OpenRouterSettingsLoading
    internal let client: OpenRouterAPIClient
    private let eventBus: EventBusProtocol
    private var contextLengthByModelId: [String: Int] = [:]
    private var pricingByModelId: [String: OpenRouterModel.Pricing] = [:]
    internal let providerName: String
    private let supportsStreamingWithTools: Bool
    internal let supportsNativeReasoning: Bool
    
    // DeepSeek V4 requires reasoning_content echoed back in every subsequent
    // assistant message. Cache the last seen reasoning per conversation.
    var reasoningContentByConversationId: [String: String] = [:]
    var lastReasoningContent: String?
    
    // Rate limiting to prevent 421 errors
    private var minRequestInterval: TimeInterval = 0.5 // 500ms between requests
    private static let providerRateLimiter = OpenRouterProviderRateLimiter()
    
    // Test configuration support
    private let testConfigurationProvider: TestConfigurationProvider

    internal static let maxToolOutputCharsForModel = 12_000

    init(
        settingsStore: any OpenRouterSettingsLoading = OpenRouterSettingsStore(),
        client: OpenRouterAPIClient = OpenRouterAPIClient(),
        eventBus: EventBusProtocol,
        providerName: String = "OpenRouter",
        supportsStreamingWithTools: Bool = true,
        supportsNativeReasoning: Bool = true,
        testConfigurationProvider: TestConfigurationProvider = TestConfigurationProvider.shared
    ) {
        self.settingsStore = settingsStore
        self.client = client
        self.eventBus = eventBus
        self.providerName = providerName
        self.supportsStreamingWithTools = supportsStreamingWithTools
        self.supportsNativeReasoning = supportsNativeReasoning
        self.testConfigurationProvider = testConfigurationProvider
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
        _ = runId
        let preparation = try buildChatPreparation(request: request)
        if preparation.toolDefinitions?.isEmpty == false, !supportsStreamingWithTools {
            return try await performChatWithHistory(request)
        }

        await logRequestStart(RequestStartContext(
            requestId: preparation.requestId,
            providerName: providerName,
            baseURL: preparation.settings.baseURL,
            streaming: true,
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
            maxTokens: outputTokenBudget(
                stage: request.stage,
                hasTools: (preparation.toolDefinitions?.isEmpty == false)
            ),
            temperature: nil,
            tools: preparation.toolDefinitions,
            toolChoice: preparation.toolChoice,
            reasoning: preparation.nativeReasoningConfiguration.map(OpenRouterChatRequest.Reasoning.init),
            stream: true  // Enable streaming
        )

        let body = try JSONEncoder().encode(requestBody)
        let requestId = preparation.requestId
        await logRequestBody(requestId: requestId, bytes: body.count)
        await logRequestBodyContent(requestId: requestId, body: body)

        // Collect streaming chunks using a thread-safe wrapper
        final class ChunkCollector: @unchecked Sendable {
            var chunks: [String] = []
            var chunkCount: Int = 0
            var reasoningChunks: [String] = []
            var usage: OpenRouterChatUsage?
            
            struct ToolCallDraft {
                var id: String
                var type: String
                var name: String
                var arguments: String
            }
            var toolCallsDrafts: [Int: ToolCallDraft] = [:]
            
            let lock = NSLock()
            
            func appendChunk(_ content: String) {
                lock.lock()
                defer { lock.unlock() }
                chunks.append(content)
            }
            
            func appendReasoningChunk(_ content: String) {
                lock.lock()
                defer { lock.unlock() }
                reasoningChunks.append(content)
            }
            
            func appendToolCalls(_ calls: [OpenRouterChatResponseChunkToolCall]) {
                lock.lock()
                defer { lock.unlock() }
                
                for call in calls {
                    var draft = toolCallsDrafts[call.index] ?? ToolCallDraft(id: "", type: "function", name: "", arguments: "")
                    
                    if let id = call.id { draft.id = id }
                    if let type = call.type { draft.type = type }
                    if let name = call.function?.name { draft.name = name }
                    if let args = call.function?.arguments { draft.arguments += args }
                    
                    toolCallsDrafts[call.index] = draft
                }
            }

            func setUsage(_ usage: OpenRouterChatUsage) {
                lock.lock()
                defer { lock.unlock() }
                self.usage = usage
            }
            
            func getResults() -> (content: String, reasoning: String?, toolCalls: [AIToolCall]?, usage: OpenRouterChatUsage?) {
                lock.lock()
                defer { lock.unlock() }
                let content = chunks.joined()
                let reasoning = reasoningChunks.joined()
                
                let toolCalls = toolCallsDrafts.sorted(by: { $0.key < $1.key }).compactMap { (_, draft) -> AIToolCall? in
                    var argsDict = Self.parseToolArguments(from: draft.arguments) ?? [:]
                    if argsDict.isEmpty, !draft.arguments.isEmpty {
                        let trimmed = draft.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed != "{}" {
                            // If JSON is malformed but we have text, store raw so tools can try to handle or fail gracefully
                            argsDict = ["_raw_args_chunk": draft.arguments]
                        }
                    }
                    return AIToolCall(id: draft.id, name: draft.name, arguments: argsDict)
                }
                
                let tc = toolCalls.isEmpty ? nil : toolCalls
                return (content: content, reasoning: reasoning.isEmpty ? nil : reasoning, toolCalls: tc, usage: usage)
            }

            private static func parseToolArguments(from raw: String) -> [String: Any]? {
                func parseJSONObject(_ candidate: String) -> [String: Any]? {
                    guard let data = candidate.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data),
                          let dictionary = object as? [String: Any] else {
                        return nil
                    }
                    return dictionary
                }

                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                if let direct = parseJSONObject(trimmed) {
                    return direct
                }

                if let start = trimmed.firstIndex(of: "{"),
                   let end = trimmed.lastIndex(of: "}"),
                   start < end,
                   let bounded = parseJSONObject(String(trimmed[start...end])) {
                    return bounded
                }

                return parseJSONObject("{\(trimmed)}")
            }
        }
        
        let collector = ChunkCollector()

        // Apply rate limiting to prevent 421 errors
        try await enforceRateLimit()

        let requestContext = requestContext(baseURL: preparation.settings.baseURL)

        do {
            try await client.chatCompletionStreaming(
                apiKey: preparation.settings.apiKey,
                context: requestContext,
                body: body
            ) { [weak self] chunkJson in
                guard let self = self else { return }
                let idx = collector.chunkCount
                collector.chunkCount += 1

                // Log each raw chunk
                Task { await self.logStreamChunk(
                    requestId: requestId,
                    chunkJson: chunkJson,
                    index: idx,
                    parseSuccess: false,
                    finishReason: nil
                ) }

                // Parse the chunk — split by newline to handle multiple data: lines in one event
                let lines = chunkJson.components(separatedBy: "\n")
                var anyParsed = false
                var lastReason: String?
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    guard let chunkData = trimmed.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(OpenRouterChatResponseChunk.self, from: chunkData)
                    else { continue }
                    anyParsed = true
                    if chunk.choices.first?.finishReason != nil {
                        lastReason = chunk.choices.first?.finishReason
                    }
                    if let usage = chunk.usage {
                        collector.setUsage(usage)
                    }
                    if let delta = chunk.choices.first?.delta {
                        if let reasoning = delta.reasoning ?? delta.reasoningContent {
                            collector.appendReasoningChunk(reasoning)
                            Task { @MainActor in
                                self.eventBus.publish(LocalModelStreamingReasoningChunkEvent(
                                    runId: runId,
                                    chunk: reasoning
                                ))
                            }
                        }
                        if let content = delta.content {
                            collector.appendChunk(content)
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
                let overallSuccess = anyParsed || lines.isEmpty
                Task { await self.logStreamChunk(
                    requestId: requestId,
                    chunkJson: chunkJson,
                    index: idx,
                    parseSuccess: overallSuccess,
                    finishReason: lastReason
                ) }
            }
            
            // Cache reasoning_content for DeepSeek V4 round-trip requirement
            let results = collector.getResults()
            if let reasoning = results.reasoning, !reasoning.isEmpty {
                lastReasoningContent = reasoning
            }
        } catch {
            try await handlePotentialRateLimit(error, requestId: preparation.requestId)
            throw error
        }

        // Get collected results
        let results = collector.getResults()
        let recoveredToolCalls = recoverFallbackToolCalls(
            from: results.content,
            structuredToolCalls: results.toolCalls,
            toolsWereProvided: preparation.toolDefinitions?.isEmpty == false
        )
        let displayContent = contentExcludingRecoveredToolCalls(
            from: results.content,
            recoveredToolCalls: recoveredToolCalls
        )
        let fullContent = sanitizeAssistantContent(displayContent)
        if let usage = results.usage {
            try await publishUsageUpdateIfAvailable(
                usage: usage,
                modelId: preparation.settings.model,
                apiKey: preparation.settings.apiKey,
                baseURL: preparation.settings.baseURL,
                runId: request.runId
            )
        }

        // Log success
        await logRequestSuccess(
            requestId: preparation.requestId,
            contentLength: fullContent?.count ?? 0,
            toolCalls: recoveredToolCalls?.count ?? 0,
            responseBytes: 0
        )

        await Self.providerRateLimiter.registerSuccess()
        publishProviderIssueResolved()

        return AIServiceResponse(
            content: fullContent,
            toolCalls: recoveredToolCalls,
            reasoning: results.reasoning
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
            providerName: providerName,
            baseURL: preparation.settings.baseURL,
            streaming: false,
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
            maxTokens: outputTokenBudget(
                stage: request.stage,
                hasTools: (preparation.toolDefinitions?.isEmpty == false)
            ),
            temperature: nil,
            tools: preparation.toolDefinitions,
            toolChoice: preparation.toolChoice,
            reasoning: preparation.nativeReasoningConfiguration.map(OpenRouterChatRequest.Reasoning.init),
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

        if let usage = response.usage {
            try await publishUsageUpdateIfAvailable(
                usage: usage,
                modelId: preparation.settings.model,
                apiKey: preparation.settings.apiKey,
                baseURL: preparation.settings.baseURL,
                runId: request.runId
            )
        }

        await logRequestSuccess(
            requestId: preparation.requestId,
            contentLength: choice.message.content?.count ?? 0,
            toolCalls: choice.message.toolCalls?.count ?? 0,
            responseBytes: data.count
        )

        await Self.providerRateLimiter.registerSuccess()
        publishProviderIssueResolved()

        let resolvedToolCalls = recoverFallbackToolCalls(
            from: choice.message.content,
            structuredToolCalls: request.tools?.isEmpty == false ? choice.message.toolCalls : nil,
            toolsWereProvided: request.tools?.isEmpty == false
        )
        let sanitizedContent = sanitizeAssistantContent(
            contentExcludingRecoveredToolCalls(
                from: choice.message.content,
                recoveredToolCalls: resolvedToolCalls
            )
        )

        let effectiveReasoning = choice.message.reasoning ?? choice.message.reasoningContent
        if let reasoning = effectiveReasoning, !reasoning.isEmpty {
            lastReasoningContent = reasoning
        }

        return AIServiceResponse(
            content: sanitizedContent,
            toolCalls: resolvedToolCalls,
            reasoning: effectiveReasoning
        )
    }

    private func fetchContextLength(modelId: String, apiKey: String, baseURL: String) async throws -> Int? {
        if let cached = contextLengthByModelId[modelId] {
            return cached
        }
        let requestContext = requestContext(baseURL: baseURL)
        let models = try await client.fetchModels(apiKey: apiKey, context: requestContext)
        guard let model = models.first(where: { $0.id == modelId }) else {
            return nil
        }
        if let contextLength = model.contextLength {
            contextLengthByModelId[modelId] = contextLength
        }
        if let pricing = model.pricing {
            pricingByModelId[modelId] = pricing
        }
        return model.contextLength
    }

    private func publishUsageUpdateIfAvailable(
        usage: OpenRouterChatUsage,
        modelId: String,
        apiKey: String,
        baseURL: String,
        runId: String?
    ) async throws {
        guard let normalizedUsage = normalizeUsage(usage) else {
            return
        }

        let estimatedCostMicrodollars = try? await estimateCostMicrodollars(
            modelId: modelId,
            promptTokens: normalizedUsage.promptTokens,
            completionTokens: normalizedUsage.completionTokens,
            apiKey: apiKey,
            baseURL: baseURL
        )
        let costMicrodollars = resolvedCostMicrodollars(
            usage: usage,
            fallback: estimatedCostMicrodollars
        )
        let accountBalanceMicrodollars = try? await fetchAccountBalanceMicrodollarsIfAvailable(
            apiKey: apiKey,
            baseURL: baseURL
        )
        if let accountBalanceMicrodollars {
            await MainActor.run {
                eventBus.publish(RemoteAIAccountBalanceUpdatedEvent(
                    providerName: providerName,
                    modelId: modelId,
                    runId: runId,
                    accountBalanceMicrodollars: accountBalanceMicrodollars
                ))
            }
        }
        let contextLength = try? await fetchContextLength(
            modelId: modelId,
            apiKey: apiKey,
            baseURL: baseURL
        )
        let event = OpenRouterUsageUpdatedEvent(
            providerName: providerName,
            modelId: modelId,
            runId: runId,
            usage: OpenRouterUsageUpdatedEvent.Usage(
                promptTokens: normalizedUsage.promptTokens,
                completionTokens: normalizedUsage.completionTokens,
                totalTokens: normalizedUsage.totalTokens,
                costMicrodollars: costMicrodollars,
                accountBalanceMicrodollars: accountBalanceMicrodollars
            ),
            contextLength: contextLength
        )
        await MainActor.run {
            eventBus.publish(event)
        }
    }

    private func normalizeUsage(_ usage: OpenRouterChatUsage) -> (promptTokens: Int, completionTokens: Int, totalTokens: Int)? {
        let promptTokens = usage.promptTokens ?? usage.inputTokens
        let completionTokens = usage.completionTokens ?? usage.outputTokens
        let totalTokens = usage.totalTokens ?? {
            guard let inputTokens = usage.inputTokens, let outputTokens = usage.outputTokens else {
                return nil
            }
            return inputTokens + outputTokens
        }()

        guard let promptTokens, let completionTokens, let totalTokens else {
            return nil
        }
        return (promptTokens, completionTokens, totalTokens)
    }

    private func estimateCostMicrodollars(
        modelId: String,
        promptTokens: Int,
        completionTokens: Int,
        apiKey: String,
        baseURL: String
    ) async throws -> Int? {
        let pricing = try await fetchPricing(modelId: modelId, apiKey: apiKey, baseURL: baseURL)
        guard let pricing else { return nil }
        let promptPricePerToken = decimalPrice(from: pricing.prompt)
        let completionPricePerToken = decimalPrice(from: pricing.completion)
        guard promptPricePerToken != 0 || completionPricePerToken != 0 else { return 0 }

        let estimatedCostDollars =
            (promptPricePerToken * Decimal(promptTokens))
            + (completionPricePerToken * Decimal(completionTokens))
        let estimatedCostMicrodollars = estimatedCostDollars * Decimal(1_000_000)
        return NSDecimalNumber(decimal: estimatedCostMicrodollars).intValue
    }

    private func fetchPricing(
        modelId: String,
        apiKey: String,
        baseURL: String
    ) async throws -> OpenRouterModel.Pricing? {
        if let cached = pricingByModelId[modelId] {
            return cached
        }

        let requestContext = requestContext(baseURL: baseURL)
        let models = try await client.fetchModels(apiKey: apiKey, context: requestContext)
        guard let model = models.first(where: { $0.id == modelId }) else {
            return nil
        }
        if let contextLength = model.contextLength {
            contextLengthByModelId[modelId] = contextLength
        }
        if let pricing = model.pricing {
            pricingByModelId[modelId] = pricing
        }
        return model.pricing
    }

    private func decimalPrice(from value: String?) -> Decimal {
        guard let value,
              let decimal = Decimal(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return decimal
    }

    private func executeChatCompletion(
        apiKey: String,
        baseURL: String,
        body: Data,
        requestId: String
    ) async throws -> Data {
        // Apply rate limiting to prevent 421 errors
        try await enforceRateLimit()
        let config = await testConfigurationProvider.configuration
        
        do {
            let requestContext = requestContext(baseURL: baseURL)
            return try await executeChatCompletionWithTimeout(
                timeoutSeconds: config.externalAPITimeout,
                requestId: requestId
            ) {
                try await self.client.chatCompletion(
                    apiKey: apiKey,
                    context: requestContext,
                    body: body
                )
            }
        } catch {
            if let openRouterError = error as? OpenRouterServiceError {
                if case let .serverError(code, body) = openRouterError {
                    let snippet = (body ?? "").prefix(2000)
                    await logRequestError(requestId: requestId, status: code, bodySnippet: String(snippet))
                }
            }
            try await handlePotentialRateLimit(error, requestId: requestId)
            await publishProviderFailureIfNeeded(error)
            throw error
        }
    }

    private func executeChatCompletionWithTimeout<T: Sendable>(
        timeoutSeconds: TimeInterval,
        requestId: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let effectiveTimeoutSeconds = max(timeoutSeconds, 1)

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(effectiveTimeoutSeconds * 1_000_000_000))
                throw AppError.aiServiceError(
                    "\(self.providerName) request timed out after \(Int(effectiveTimeoutSeconds))s (requestId: \(requestId))"
                )
            }

            defer {
                group.cancelAll()
            }

            guard let result = try await group.next() else {
                throw AppError.aiServiceError("\(providerName) request ended without a result (requestId: \(requestId))")
            }
            return result
        }
    }
    
    /// Enforces rate limiting to prevent 421 errors from OpenRouter
    private func enforceRateLimit() async throws {
        let config = await testConfigurationProvider.configuration
        
        // Skip rate limiting if external APIs are disabled
        guard config.allowExternalAPIs else {
            throw AppError.aiServiceError("External APIs are disabled in test configuration")
        }
        
        let now = Date()
        let effectiveInterval = max(minRequestInterval, config.minAPIRequestInterval)
        let reservation = await Self.providerRateLimiter.reserveWait(
            minimumInterval: effectiveInterval,
            now: now
        )
        let waitTime = reservation.waitTime

        if waitTime > 0 {
            if reservation.isProviderCooldown {
                let cooldownUntil = now.addingTimeInterval(waitTime)
                eventBus.publish(ProviderIssueStatusEvent(
                    providerName: "OpenRouter",
                    statusKind: .rateLimited,
                    statusCode: nil,
                    message: "Provider cooldown active. Waiting before the next request.",
                    cooldownUntil: cooldownUntil
                ))
            }
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
    }

    private func handlePotentialRateLimit(_ error: Error, requestId: String) async throws {
        guard let serviceError = error as? OpenRouterServiceError,
              case let .serverError(code, _) = serviceError,
              isProviderRateLimitStatus(code)
        else {
            return
        }

        let cooldownDuration = await Self.providerRateLimiter.registerRateLimit(statusCode: code)

        await AppLogger.shared.error(
            category: .ai,
            message: "openrouter.rate_limit_hit",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": requestId,
                "statusCode": code,
                "retrySuggested": true,
                "providerCooldownSeconds": Int(cooldownDuration)
            ])
        )

        let cooldownUntil = Date().addingTimeInterval(cooldownDuration)
        let issueMessage = providerIssueMessage(
            for: serviceError,
            fallback: "Provider rate limit hit. Retrying when cooldown ends."
        )
        eventBus.publish(ProviderIssueStatusEvent(
            providerName: providerName,
            statusKind: .rateLimited,
            statusCode: code,
            message: issueMessage,
            cooldownUntil: cooldownUntil
        ))
    }

    private func isProviderRateLimitStatus(_ statusCode: Int) -> Bool {
        statusCode == 421 || statusCode == 429
    }

    private func publishProviderFailureIfNeeded(_ error: Error) async {
        guard let serviceError = error as? OpenRouterServiceError else {
            return
        }

        let resolvedIssueStatus = providerIssueStatus(for: serviceError)
        let issueKind = resolvedIssueStatus.kind
        let issueStatusCode = resolvedIssueStatus.statusCode
        let issueMessage = providerIssueMessage(
            for: serviceError,
            fallback: error.localizedDescription
        )

        eventBus.publish(ProviderIssueStatusEvent(
            providerName: providerName,
            statusKind: issueKind,
            statusCode: issueStatusCode,
            message: issueMessage,
            cooldownUntil: nil
        ))
    }

    private func publishProviderIssueResolved() {
        eventBus.publish(ProviderIssueStatusEvent(
            providerName: providerName,
            statusKind: .resolved,
            statusCode: nil,
            message: "",
            cooldownUntil: nil
        ))
    }

    private func providerIssueStatus(
        for error: OpenRouterServiceError
    ) -> (kind: ProviderIssueStatusEvent.StatusKind, statusCode: Int?) {
        switch error {
        case let .serverError(code, _):
            switch code {
            case 401, 403:
                return (.authentication, code)
            case 402:
                return (.insufficientBalance, code)
            case 421, 429:
                return (.rateLimited, code)
            case 500...599:
                return (.unavailable, code)
            default:
                return (.unknown, code)
            }
        default:
            return (.transport, nil)
        }
    }

    private func providerIssueMessage(
        for error: OpenRouterServiceError,
        fallback: String
    ) -> String {
        switch error {
        case let .serverError(code, body):
            if code == 402, let insufficientBalanceMessage = insufficientBalanceMessage(from: body) {
                return insufficientBalanceMessage
            }
            let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedBody.isEmpty {
                return trimmedBody
            }
            return fallback
        default:
            return fallback
        }
    }

    private func insufficientBalanceMessage(from body: String?) -> String? {
        guard let body,
              let data = body.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObject = jsonObject["error"] as? [String: Any] else {
            return nil
        }

        let message = (errorObject["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = errorObject["metadata"] as? [String: Any]
        let buyCreditsURL = (metadata?["buyCreditsUrl"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let message, !message.isEmpty, let buyCreditsURL, !buyCreditsURL.isEmpty {
            return "\(message) Add credits: \(buyCreditsURL)"
        }
        if let message, !message.isEmpty {
            return message
        }
        return nil
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
            eventBus.publish(ProviderIssueStatusEvent(
                providerName: providerName,
                statusKind: .unknown,
                statusCode: nil,
                message: "Failed to decode provider response.",
                cooldownUntil: nil
            ))
            throw AppError.aiServiceError("Failed to decode OpenRouter response: \(error.localizedDescription)")
        }
    }

    func decodeOpenRouterErrorMessage(from data: Data) -> String? {
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
        let providerSuffix: String
        if let providerName, !providerName.isEmpty {
            providerSuffix = " Provider: \(providerName)."
        } else {
            providerSuffix = ""
        }

        if let code = err.code, let message = err.message, !message.isEmpty {
            return "OpenRouter error (\(code)): \(message).\(providerSuffix)"
        }
        if let message = err.message, !message.isEmpty {
            return "OpenRouter error: \(message).\(providerSuffix)"
        }
        return nil
    }

    private func outputTokenBudget(stage: AIRequestStage?, hasTools: Bool) -> Int {
        switch stage {
        case .tool_loop:
            return hasTools ? 2048 : 420
        case .final_response:
            return 500
        case .initial_response:
            return hasTools ? 420 : 640
        case .qa_tool_output_review, .qa_quality_review:
            return 520
        case .warmup, .other, .none:
            return hasTools ? 420 : 640
        }
    }

    private func sanitizeAssistantContent(_ content: String?) -> String? {
        guard let content else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func refreshAccountBalance(runId: String?) async {
        let settings = settingsStore.load(includeApiKey: true)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }
        guard let accountBalanceMicrodollars = try? await fetchAccountBalanceMicrodollarsIfAvailable(
            apiKey: apiKey,
            baseURL: settings.baseURL
        ) else {
            return
        }

        await MainActor.run {
            eventBus.publish(RemoteAIAccountBalanceUpdatedEvent(
                providerName: providerName,
                modelId: settings.model,
                runId: runId,
                accountBalanceMicrodollars: accountBalanceMicrodollars
            ))
        }
    }

    private func requestContext(baseURL: String) -> OpenRouterAPIClient.RequestContext {
        if providerName == "Kilo Code" || baseURL.contains("api.kilo.ai") {
            return OpenRouterAPIClient.RequestContext(
                baseURL: baseURL,
                appName: "Kilo Code",
                referer: "https://kilocode.ai"
            )
        }

        return OpenRouterAPIClient.RequestContext(
            baseURL: baseURL,
            appName: "OSX IDE",
            referer: ""
        )
    }

    private func resolvedCostMicrodollars(
        usage: OpenRouterChatUsage,
        fallback: Int?
    ) -> Int? {
        if let costMicrodollars = usage.costMicrodollars {
            return costMicrodollars
        }
        if providerName == "Kilo Code",
           let upstreamCost = usage.costDetails?.upstreamInferenceCost {
            return microdollars(fromDollarAmount: upstreamCost)
        }
        if let directCost = usage.cost {
            return microdollars(fromDollarAmount: directCost)
        }
        return fallback
    }

    private func fetchAccountBalanceMicrodollarsIfAvailable(
        apiKey: String,
        baseURL: String
    ) async throws -> Int? {
        if providerName == "Kilo Code" || baseURL.contains("api.kilo.ai") {
            guard let apiBaseURL = kiloAPIBaseURL(from: baseURL) else { return nil }
            guard let balance = try await client.fetchKiloBalance(apiKey: apiKey, apiBaseURL: apiBaseURL) else { return nil }
            return microdollars(fromDollarAmount: balance)
        }
        if providerName == "DeepSeek" || baseURL.contains("api.deepseek.com") {
            guard let apiBaseURL = providerAPIBaseURL(from: baseURL) else { return nil }
            guard let balance = try await client.fetchDeepSeekBalance(apiKey: apiKey, apiBaseURL: apiBaseURL) else { return nil }
            return microdollars(fromDollarAmount: balance)
        }
        return nil
    }

    private func providerAPIBaseURL(from baseURL: String) -> String? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func kiloAPIBaseURL(from baseURL: String) -> String? {
        providerAPIBaseURL(from: baseURL)
    }

    private func microdollars(fromDollarAmount amount: Decimal) -> Int {
        NSDecimalNumber(decimal: amount * Decimal(1_000_000)).intValue
    }

    private func recoverFallbackToolCalls(
        from content: String?,
        structuredToolCalls: [AIToolCall]?,
        toolsWereProvided: Bool
    ) -> [AIToolCall]? {
        if let structuredToolCalls, !structuredToolCalls.isEmpty {
            return structuredToolCalls
        }
        guard toolsWereProvided, let content, !content.isEmpty else {
            return nil
        }
        return Self.extractFallbackToolCalls(from: content)
    }

    private func contentExcludingRecoveredToolCalls(
        from content: String?,
        recoveredToolCalls: [AIToolCall]?
    ) -> String? {
        guard let content else { return nil }
        guard recoveredToolCalls?.isEmpty == false else { return content }
        return Self.stripRecoveredToolCallMarkup(from: content)
    }

    nonisolated static func extractFallbackToolCalls(from content: String) -> [AIToolCall]? {
        let decoders: [(String) -> [AIToolCall]?] = [
            decodeStructuredXMLToolCalls,
            decodeLegacyToolCodeCalls,
            decodeBareFunctionCalls,
            decodeToolCallBlockContent,
            decodeMinimaxToolCalls
        ]

        for decoder in decoders {
            if let toolCalls = decoder(content), !toolCalls.isEmpty {
                return toolCalls
            }
        }

        return nil
    }

    nonisolated private static func normalizeRecoveredToolName(_ rawName: String) -> String {
        let normalized = decodeToolMarkupEntities(rawName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let aliases: [String: String] = [
            "list_directory": "list_files",
            "list_dir": "list_files",
            "cli-mcp-server_run_command": "run_command",
            "run_terminal_command": "run_command",
            "run_shell_command": "run_command",
            "create_file": "write_file",
            "write": "write_file",
            "write_file_v2": "write_file",
            "edit_file": "replace_in_file",
            "replace_in_file_v2": "replace_in_file",
            "view_file": "read_file",
            "read": "read_file",
            "read_file_v2": "read_file",
            "search_files": "search_project",
            "grep_search": "search_project",
            "find_in_files": "search_project",
            "web_fetch": "web_browse",
            "fetch_url": "web_browse",
            "http_get": "web_browse",
            "internet_search": "web_search",
            "google": "web_search",
            "search_web": "web_search",
            "apply_diff": "patch_file",
            "patch": "patch_file",
            "edit": "patch_file",
            "run_shell": "run_command",
            "bash": "run_command",
            "terminal": "run_command",
            "execute_command": "run_command"
        ]

        return aliases[normalized] ?? normalized
    }

    nonisolated private static func decodeStructuredXMLToolCalls(from content: String) -> [AIToolCall]? {
        let pattern = #"<tool_call>\s*(.*?)\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let toolPattern = #"<tool\s+name=\"([^\"]+)\"\s*>(.*?)</tool>"#
        let functionEqPattern = #"<function=([^\s>]+)>\s*(.*?)\s*</function>"#
        let argPattern = #"<arg\s+name=\"([^\"]+)\"\s*>(.*?)</arg>"#
        let parameterPattern = #"<parameter\s+name=\"([^\"]+)\"\s*>(.*?)</parameter>"#
        let parameterEqPattern = #"<parameter=([^\s>]+)>\s*(.*?)\s*</parameter>"#
        guard let toolRegex = try? NSRegularExpression(
                pattern: toolPattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let functionEqRegex = try? NSRegularExpression(
                pattern: functionEqPattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let argRegex = try? NSRegularExpression(
                pattern: argPattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let parameterRegex = try? NSRegularExpression(
                pattern: parameterPattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let parameterEqRegex = try? NSRegularExpression(
                pattern: parameterEqPattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let toolCalls = matches.flatMap { match -> [AIToolCall] in
            guard match.numberOfRanges == 2,
                  let bodyRange = Range(match.range(at: 1), in: content) else {
                return []
            }

            let body = String(content[bodyRange])
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)

            // Try standard <tool name="..."> format first, then <function=...> format
            let standardMatches = toolRegex.matches(in: body, options: [], range: bodyNSRange)
            let functionEqMatches = standardMatches.isEmpty ? functionEqRegex.matches(in: body, options: [], range: bodyNSRange) : []

            let matched = standardMatches.isEmpty ? functionEqMatches : standardMatches
            let isFunctionEqFormat = !standardMatches.isEmpty ? false : !functionEqMatches.isEmpty

            return matched.compactMap { toolMatch in
                guard toolMatch.numberOfRanges == 3,
                      let nameRange = Range(toolMatch.range(at: 1), in: body),
                      let toolBodyRange = Range(toolMatch.range(at: 2), in: body) else {
                    return nil
                }

                let toolName = normalizeRecoveredToolName(String(body[nameRange]))
                guard !toolName.isEmpty else { return nil }

                let toolBody = String(body[toolBodyRange])
                let toolBodyNSRange = NSRange(toolBody.startIndex..<toolBody.endIndex, in: toolBody)

                var arguments = recoverArguments(
                    in: toolBody,
                    range: toolBodyNSRange,
                    regex: argRegex
                )
                if arguments.isEmpty {
                    arguments = recoverArguments(
                        in: toolBody,
                        range: toolBodyNSRange,
                        regex: parameterRegex
                    )
                }
                if arguments.isEmpty, isFunctionEqFormat {
                    arguments = recoverArguments(
                        in: toolBody,
                        range: toolBodyNSRange,
                        regex: parameterEqRegex
                    )
                }

                return AIToolCall(
                    id: UUID().uuidString,
                    name: toolName,
                    arguments: arguments
                )
            }
        }

        return toolCalls.isEmpty ? nil : toolCalls
    }

    nonisolated private static func decodeLegacyToolCodeCalls(from content: String) -> [AIToolCall]? {
        let pattern = #"<tool_code>\s*(.*?)\s*</tool_code>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let paramPattern = #"<param\s+name=\"([^\"]+)\"\s*>(.*?)</param>"#
        let selfClosingToolPattern = #"<tool\s+name=\"([^\"]+)\"(.*?)/>"#
        let inlineAttributePattern = #"([a-zA-Z_][a-zA-Z0-9_\-]*)=\"(.*?)\""#
        guard let paramRegex = try? NSRegularExpression(
            pattern: paramPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let selfClosingToolRegex = try? NSRegularExpression(
            pattern: selfClosingToolPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let inlineAttributeRegex = try? NSRegularExpression(
            pattern: inlineAttributePattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let toolCalls = matches.flatMap { match -> [AIToolCall] in
            guard match.numberOfRanges == 2,
                  let bodyRange = Range(match.range(at: 1), in: content) else {
                return []
            }

            let body = String(content[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)

            let inlineTools = selfClosingToolRegex.matches(in: body, options: [], range: bodyNSRange).compactMap { toolMatch -> AIToolCall? in
                guard toolMatch.numberOfRanges == 3,
                      let nameRange = Range(toolMatch.range(at: 1), in: body),
                      let attributesRange = Range(toolMatch.range(at: 2), in: body) else {
                    return nil
                }

                let toolName = normalizeRecoveredToolName(String(body[nameRange]))
                guard !toolName.isEmpty else { return nil }

                let attributesText = String(body[attributesRange])
                let attributesNSRange = NSRange(attributesText.startIndex..<attributesText.endIndex, in: attributesText)
                var arguments: [String: Any] = [:]
                for attributeMatch in inlineAttributeRegex.matches(in: attributesText, options: [], range: attributesNSRange) {
                    guard attributeMatch.numberOfRanges == 3,
                          let keyRange = Range(attributeMatch.range(at: 1), in: attributesText),
                          let valueRange = Range(attributeMatch.range(at: 2), in: attributesText) else {
                        continue
                    }
                    let key = decodeToolMarkupEntities(String(attributesText[keyRange]))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard key != "name", !key.isEmpty else { continue }
                    let value = decodeToolMarkupEntities(String(attributesText[valueRange]))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    arguments[key] = value
                }

                return AIToolCall(
                    id: UUID().uuidString,
                    name: toolName,
                    arguments: arguments
                )
            }
            if !inlineTools.isEmpty {
                return inlineTools
            }

            let lines = body
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let firstLine = lines.first else { return [] }

            let toolName = normalizeRecoveredToolName(firstLine)
            guard !toolName.isEmpty else { return [] }

            let arguments = recoverArguments(
                in: body,
                range: bodyNSRange,
                regex: paramRegex
            )

            return [AIToolCall(
                id: UUID().uuidString,
                name: toolName,
                arguments: arguments
            )]
        }

        return toolCalls.isEmpty ? nil : toolCalls
    }

    nonisolated private static func decodeBareFunctionCalls(from content: String) -> [AIToolCall]? {
        let pattern = #"<function=([^\s>]+)>\s*(.*?)\s*</function>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let parameterPattern = #"<parameter=([^\s>]+)>\s*(.*?)\s*</parameter>"#
        let namedParameterPattern = #"<parameter\s+name=\"([^\"]+)\"\s*>(.*?)</parameter>"#
        guard let paramRegex = try? NSRegularExpression(
            pattern: parameterPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ), let namedParamRegex = try? NSRegularExpression(
            pattern: namedParameterPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let toolCalls = matches.compactMap { match -> AIToolCall? in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: content),
                  let bodyRange = Range(match.range(at: 2), in: content) else {
                return nil
            }

            let toolName = normalizeRecoveredToolName(String(content[nameRange]))
            guard !toolName.isEmpty else { return nil }

            let body = String(content[bodyRange])
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)

            var arguments = recoverArguments(in: body, range: bodyNSRange, regex: paramRegex)
            if arguments.isEmpty {
                arguments = recoverArguments(in: body, range: bodyNSRange, regex: namedParamRegex)
            }

            return AIToolCall(
                id: UUID().uuidString,
                name: toolName,
                arguments: arguments
            )
        }

        return toolCalls.isEmpty ? nil : toolCalls
    }

    nonisolated private static func decodeToolCallBlockContent(from content: String) -> [AIToolCall]? {
        let parts = content.components(separatedBy: "<tool_call>")
        guard parts.count > 1 else { return nil }

        var toolCalls: [AIToolCall] = []
        for part in parts.dropFirst() {
            let body: String
            if let closeRange = part.range(of: "</tool_call>", options: .caseInsensitive) {
                body = String(part[..<closeRange.lowerBound])
            } else {
                body = part
            }

            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let lines = trimmed.components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }

            let path = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, path.hasPrefix("/") || path.hasPrefix(".") else { continue }

            let fileContent = lines.dropFirst().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileContent.isEmpty else { continue }

            toolCalls.append(AIToolCall(
                id: UUID().uuidString,
                name: "write_file",
                arguments: ["path": path, "content": fileContent]
            ))
        }

        return toolCalls.isEmpty ? nil : toolCalls
    }

    nonisolated private static func decodeMinimaxToolCalls(from content: String) -> [AIToolCall]? {
        let pattern = #"<invoke\s+name=\"([^\"]+)\"\s*>(.*?)</invoke>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let parameterPattern = #"<parameter\s+name=\"([^\"]+)\"\s*>(.*?)</parameter>"#
        guard let parameterRegex = try? NSRegularExpression(
            pattern: parameterPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let toolCalls = matches.compactMap { match -> AIToolCall? in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: content),
                  let bodyRange = Range(match.range(at: 2), in: content) else {
                return nil
            }

            let toolName = normalizeRecoveredToolName(String(content[nameRange]))
            guard !toolName.isEmpty else { return nil }

            let body = String(content[bodyRange])
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)
            let arguments = recoverArguments(
                in: body,
                range: bodyNSRange,
                regex: parameterRegex
            )

            return AIToolCall(
                id: UUID().uuidString,
                name: toolName,
                arguments: arguments
            )
        }

        return toolCalls.isEmpty ? nil : toolCalls
    }

    nonisolated private static func stripRecoveredToolCallMarkup(from content: String) -> String {
        var output = content
        let patterns = [
            #"(?is)<tool_call>\s*.*?\s*</tool_call>"#,
            #"(?is)<tool_code>\s*.*?\s*</tool_code>"#,
            #"(?is)<minimax:tool_call>\s*.*?\s*</minimax:tool_call>"#,
            #"(?is)<invoke\s+name=\"[^\"]+\"\s*>.*?</invoke>"#,
            #"(?is)<tool\s+name=\"[^\"]+\"\s*>.*?</tool>"#,
            #"(?is)</?arg\s+name=\"[^\"]+\">"#,
            #"(?is)</?parameter\s+name=\"[^\"]+\">"#,
            #"(?is)</?param\s+name=\"[^\"]+\">"#,
            #"(?is)<function=[^\s>]+>\s*|</function>"#,
            #"(?is)<parameter=[^\s>]+>\s*|</parameter>"#
        ]

        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func decodeToolMarkupEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    nonisolated private static func recoverArguments(
        in body: String,
        range: NSRange,
        regex: NSRegularExpression
    ) -> [String: Any] {
        let parameters = regex.matches(in: body, options: [], range: range)
        var arguments: [String: Any] = [:]
        for parameter in parameters {
            guard parameter.numberOfRanges == 3,
                  let parameterNameRange = Range(parameter.range(at: 1), in: body),
                  let parameterValueRange = Range(parameter.range(at: 2), in: body) else {
                continue
            }
            let parameterName = decodeToolMarkupEntities(String(body[parameterNameRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !parameterName.isEmpty else { continue }
            let parameterValue = decodeToolMarkupEntities(String(body[parameterValueRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            arguments[parameterName] = parameterValue
        }
        return arguments
    }
}
