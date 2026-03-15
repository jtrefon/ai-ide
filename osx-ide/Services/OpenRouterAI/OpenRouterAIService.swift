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

actor OpenRouterAIService: AIService {
    internal let settingsStore: any OpenRouterSettingsLoading
    internal let client: OpenRouterAPIClient
    private let eventBus: EventBusProtocol
    private var contextLengthByModelId: [String: Int] = [:]
    private var pricingByModelId: [String: OpenRouterModel.Pricing] = [:]
    private let providerName: String
    private let supportsStreamingWithTools: Bool
    internal let supportsNativeReasoning: Bool
    
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
        await logRequestBody(requestId: preparation.requestId, bytes: body.count)

        // Collect streaming chunks using a thread-safe wrapper
        final class ChunkCollector: @unchecked Sendable {
            var chunks: [String] = []
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
            
            func getResults() -> (content: String, toolCalls: [AIToolCall]?, usage: OpenRouterChatUsage?) {
                lock.lock()
                defer { lock.unlock() }
                let content = chunks.joined()
                
                let toolCalls = toolCallsDrafts.sorted(by: { $0.key < $1.key }).compactMap { (_, draft) -> AIToolCall? in
                    var argsDict = Self.parseToolArguments(from: draft.arguments) ?? [:]
                    if argsDict.isEmpty, !draft.arguments.isEmpty {
                        // If JSON is malformed but we have text, store raw so tools can try to handle or fail gracefully
                        argsDict = ["_raw_args_chunk": draft.arguments]
                    }
                    return AIToolCall(id: draft.id, name: draft.name, arguments: argsDict)
                }
                
                let tc = toolCalls.isEmpty ? nil : toolCalls
                return (content, tc, usage)
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

        let requestContext = OpenRouterAPIClient.RequestContext(
            baseURL: preparation.settings.baseURL,
            appName: "OSX IDE",
            referer: ""
        )

        do {
            try await client.chatCompletionStreaming(
                apiKey: preparation.settings.apiKey,
                context: requestContext,
                body: body
            ) { [weak self] chunkJson in
                guard let self = self else { return }

                // Parse the chunk
                if let chunkData = chunkJson.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(OpenRouterChatResponseChunk.self, from: chunkData) {
                    if let usage = chunk.usage {
                        collector.setUsage(usage)
                    }
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
        } catch {
            try await handlePotentialRateLimit(error, requestId: preparation.requestId)
            throw error
        }

        // Get collected results
        let results = collector.getResults()
        let fullContent = sanitizeAssistantContent(results.content)
        let toolCalls = results.toolCalls
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
            toolCalls: toolCalls?.count ?? 0,
            responseBytes: 0
        )

        await Self.providerRateLimiter.registerSuccess()
        publishProviderIssueResolved()

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

        let resolvedToolCalls = request.tools?.isEmpty == false
            ? choice.message.toolCalls
            : nil

        return AIServiceResponse(
            content: choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        let costMicrodollars = usage.costMicrodollars ?? estimatedCostMicrodollars
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
                costMicrodollars: costMicrodollars
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
            let requestContext = OpenRouterAPIClient.RequestContext(
                baseURL: baseURL,
                appName: "OSX IDE",
                referer: ""
            )
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

    private func outputTokenBudget(stage: AIRequestStage?, hasTools: Bool) -> Int {
        switch stage {
        case .tool_loop:
            return hasTools ? 2048 : 420
        case .final_response:
            return 500
        case .initial_response, .strategic_planning, .tactical_planning:
            return hasTools ? 420 : 640
        case .qa_tool_output_review, .qa_quality_review:
            return 520
        case .warmup, .other, .none:
            return hasTools ? 420 : 640
        }
    }

    private func sanitizeAssistantContent(_ content: String?) -> String? {
        guard let content else { return nil }
        let split = ChatPromptBuilder.splitReasoning(from: content)
        let cleaned = split.content
            .replacingOccurrences(of: #"(?is)</?think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
