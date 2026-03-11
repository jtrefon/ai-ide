import Foundation
import Combine
import MLX
@preconcurrency import MLXLMCommon
import MLXLLM
import MLXVLM
import Tokenizers
import Darwin

protocol MemoryPressureObserving: Sendable {}

private struct LocalModelTestBudget {
    static let maximumOperationalContextLength = 8192
    static let maximumOperationalOutputTokens = 1024

    let contextLength: Int
    let retainedMessages: [ChatMessage]
    let maxOutputTokens: Int

    static func applyIfNeeded(to request: AIServiceHistoryRequest, contextLength: Int) -> LocalModelTestBudget {
        guard AppRuntimeEnvironment.launchContext.isTesting else {
            let clampedContextLength = min(contextLength, maximumOperationalContextLength)
            let defaultMaxOutputTokens = min(
                maximumOperationalOutputTokens,
                max(512, clampedContextLength / 4)
            )
            return LocalModelTestBudget(
                contextLength: clampedContextLength,
                retainedMessages: request.messages,
                maxOutputTokens: defaultMaxOutputTokens
            )
        }

        let clampedContextLength = min(contextLength, 2048)
        let retainedMessages = trimMessages(request.messages, maxMessages: 4)
        return LocalModelTestBudget(
            contextLength: clampedContextLength,
            retainedMessages: retainedMessages,
            maxOutputTokens: min(768, max(384, clampedContextLength / 3))
        )
    }

    private static func trimMessages(_ messages: [ChatMessage], maxMessages: Int) -> [ChatMessage] {
        guard messages.count > maxMessages else { return messages }
        return Array(messages.suffix(maxMessages))
    }
}

/// Helper class to manage memory pressure observation with a closure callback
final class MemoryPressureObserver: MemoryPressureObserving, @unchecked Sendable {
    private var observer: NSObjectProtocol?
    private let onMemoryPressure: @Sendable () -> Void

    init(onMemoryPressure: @escaping @Sendable () -> Void) {
        self.onMemoryPressure = onMemoryPressure
        setupObserver()
    }

    private func setupObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSMemoryWarningNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onMemoryPressure()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

actor LocalModelProcessAIService: AIService {
    typealias MemoryPressureObserverFactory = @Sendable (@escaping @Sendable () -> Void) -> (any MemoryPressureObserving)?

    struct NoOpEventBus: EventBusProtocol {
        func publish<E: Event>(_ event: E) {}

        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            AnyCancellable {}
        }
    }

    protocol ModelFileStoring: Sendable {
        func isModelInstalled(_ model: LocalModelDefinition) -> Bool
        func modelDirectory(modelId: String) throws -> URL
        func runtimeModelDirectory(for model: LocalModelDefinition) throws -> URL
    }

    struct LocalModelFileStoreAdapter: ModelFileStoring {
        func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
            LocalModelFileStore.isModelInstalled(model)
        }

        func modelDirectory(modelId: String) throws -> URL {
            try LocalModelFileStore.modelDirectory(modelId: modelId)
        }

        func runtimeModelDirectory(for model: LocalModelDefinition) throws -> URL {
            try LocalModelFileStore.runtimeModelDirectory(for: model)
        }
    }

    protocol LocalModelGenerating: Sendable {
        func generate(modelDirectory: URL, userInput: sending UserInput, tools: [ToolSpec]?, toolCallFormat: ToolCallFormat?, runId: String?, contextLength: Int, maxOutputTokens: Int, conversationId: String?) async throws -> AIServiceResponse
    }

    actor NativeMLXGenerator: LocalModelGenerating {
        private let eventBus: EventBusProtocol
        private var containersByModelDirectory: [URL: ModelContainer] = [:]
        private var accessOrder: [URL] = []
        private let maxCachedModels = 1  // Conservative - one model at a time given memory constraints
        private var generationCount: Int = 0
        private static let mlxCacheLimitBytes = 256 * 1024 * 1024  // 256 MB Metal buffer pool cap
        private static let defaultTestingRSSLimitMB = 8 * 1024
        private static let defaultOperationalRSSLimitMB = 10 * 1024

        init(eventBus: EventBusProtocol) {
            self.eventBus = eventBus
            Memory.cacheLimit = Self.mlxCacheLimitBytes
        }

        private func performInference<R>(_ body: @escaping @Sendable () async throws -> R) async throws -> R {
            return try await body()
        }

        func generate(modelDirectory: URL, userInput: sending UserInput, tools: [ToolSpec]?, toolCallFormat: ToolCallFormat? = nil, runId: String?, contextLength: Int, maxOutputTokens: Int, conversationId: String? = nil) async throws -> AIServiceResponse {
            print("[LOCAL-MLX] generate modelDirectory=\(modelDirectory.path) toolCallFormat=\(String(describing: toolCallFormat)) contextLength=\(contextLength) maxOutputTokens=\(maxOutputTokens)")
            let preparedUserInput = userInput
            let rssLimitMB = Self.resolvedRSSLimitMB()

            // Cap KV cache size to prevent unbounded memory growth during long conversations.
            // Uses RotatingKVCache which overwrites old entries beyond this limit.
            let maxKVSize = contextLength

            let parameters = GenerateParameters(
                maxTokens: maxOutputTokens,
                maxKVSize: maxKVSize
            )
            let eventBus = self.eventBus

            do {
                let response = try await performInference {
                    let container = try await self.loadContainerCached(modelDirectory: modelDirectory, toolCallFormat: toolCallFormat)
                    return try await container.perform { context in
                        try Self.throwIfProcessRSSExceeded(limitMB: rssLimitMB, phase: "before_generation")

                        let input = try await context.processor.prepare(input: preparedUserInput)
                        let stream = try MLXLMCommon.generate(
                            input: input,
                            parameters: parameters,
                            context: context
                        )

                        var output = ""
                        var collectedToolCalls: [AIToolCall] = []

                        func publishStatus(_ message: String) async {
                            guard let runId else { return }
                            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            await MainActor.run {
                                eventBus.publish(LocalModelStreamingStatusEvent(runId: runId, message: message))
                            }
                        }

                        for await generation in stream {
                            try Self.throwIfProcessRSSExceeded(limitMB: rssLimitMB, phase: "streaming")

                            switch generation {
                            case .chunk(let text):
                                output.append(text)
                                if collectedToolCalls.isEmpty,
                                   let earlyFallbackToolCalls = Self.extractFallbackToolCalls(
                                    from: output,
                                    toolsWereProvided: !(tools?.isEmpty ?? true),
                                    structuredToolCallsWereDetected: false,
                                    toolCallFormat: toolCallFormat
                                   ),
                                   !earlyFallbackToolCalls.isEmpty {
                                    collectedToolCalls = earlyFallbackToolCalls
                                    await publishStatus("Recovered fallback tool call from streamed output")
                                    break
                                }
                                if let runId, !text.isEmpty {
                                    await MainActor.run {
                                        eventBus.publish(LocalModelStreamingChunkEvent(runId: runId, chunk: text))
                                    }
                                }
                            case .info:
                                break
                            case .toolCall(let toolCall):
                                collectedToolCalls.append(Self.makeAIToolCall(from: toolCall))
                                await publishStatus("Structured tool call detected: \(toolCall.function.name)")
                            }
                        }
                        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        let fallbackToolCalls = Self.extractFallbackToolCalls(
                            from: trimmedOutput,
                            toolsWereProvided: !(tools?.isEmpty ?? true),
                            structuredToolCallsWereDetected: !collectedToolCalls.isEmpty,
                            toolCallFormat: toolCallFormat
                        )
                        let resolvedToolCalls = collectedToolCalls.isEmpty ? fallbackToolCalls : collectedToolCalls
                        let shouldSuppressToolCallPayloadFromContent = !(resolvedToolCalls?.isEmpty ?? true)
                        return AIServiceResponse(
                            content: trimmedOutput.isEmpty || shouldSuppressToolCallPayloadFromContent ? nil : trimmedOutput,
                            toolCalls: resolvedToolCalls
                        )
                    }
                }

                generationCount += 1
                logMLXMemorySnapshot()
                if AppRuntimeEnvironment.launchContext.isTesting {
                    unloadModel(modelDirectory: modelDirectory)
                }

                return response
            } catch {
                unloadModel(modelDirectory: modelDirectory)
                throw error
            }
        }

        private func synchronizeMLXStream() {
            Stream().synchronize()
        }

        private func logMLXMemorySnapshot() {
            let snapshot = Memory.snapshot()
            print("[MLXMemory] gen=\(generationCount) active=\(snapshot.activeMemory / (1024*1024))MB cache=\(snapshot.cacheMemory / (1024*1024))MB peak=\(snapshot.peakMemory / (1024*1024))MB")
        }

        nonisolated private static func resolvedRSSLimitMB() -> Int {
            let environment = ProcessInfo.processInfo.environment
            if let configured = environment["OSXIDE_LOCAL_MODEL_MAX_RSS_MB"],
               let parsed = Int(configured),
               parsed > 0 {
                return parsed
            }

            return AppRuntimeEnvironment.launchContext.isTesting
                ? defaultTestingRSSLimitMB
                : defaultOperationalRSSLimitMB
        }

        nonisolated private static func throwIfProcessRSSExceeded(limitMB: Int, phase: String) throws {
            let rssMB = currentProcessRSSMB()
            guard rssMB < limitMB else {
                throw AppError.aiServiceError(
                    "Local model memory budget exceeded during \(phase): \(rssMB)MB used with limit \(limitMB)MB"
                )
            }
        }

        nonisolated private static func currentProcessRSSMB() -> Int {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)

            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundPointer, &count)
                }
            }

            guard result == KERN_SUCCESS else { return 0 }
            return Int(info.resident_size / 1024 / 1024)
        }

        nonisolated private static func makeAIToolCall(from toolCall: ToolCall) -> AIToolCall {
            let arguments = toolCall.function.arguments.mapValues { $0.anyValue }
            return AIToolCall(
                id: UUID().uuidString,
                name: toolCall.function.name,
                arguments: arguments
            )
        }

        nonisolated static func extractFallbackToolCalls(
            from content: String,
            toolsWereProvided: Bool,
            structuredToolCallsWereDetected: Bool,
            toolCallFormat: ToolCallFormat?
        ) -> [AIToolCall]? {
            guard toolsWereProvided, !structuredToolCallsWereDetected else { return nil }
            guard !content.isEmpty else { return nil }

            if let directCall = decodeFallbackToolCall(from: content) {
                return [directCall]
            }

            if let wrappedCalls = decodeFallbackToolCallsEnvelope(from: content), !wrappedCalls.isEmpty {
                return wrappedCalls
            }

            if let fencedJSON = extractFirstJSONCodeBlock(from: content) {
                if let directCall = decodeFallbackToolCall(from: fencedJSON) {
                    return [directCall]
                }
                if let wrappedCalls = decodeFallbackToolCallsEnvelope(from: fencedJSON), !wrappedCalls.isEmpty {
                    return wrappedCalls
                }
            }

            return nil
        }

        nonisolated private static func regexMatches(in text: String, pattern: String) -> [String] {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            ) else {
                return []
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return expression.matches(in: text, options: [], range: range).compactMap { match in
                guard let matchRange = Range(match.range, in: text) else { return nil }
                return String(text[matchRange])
            }
        }

        nonisolated private static func regexCaptureGroups(in text: String, pattern: String) -> [[String]] {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            ) else {
                return []
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return expression.matches(in: text, options: [], range: range).map { match in
                guard match.numberOfRanges > 1 else { return [] }
                return (1..<match.numberOfRanges).compactMap { index in
                    let groupRange = match.range(at: index)
                    guard groupRange.location != NSNotFound,
                          let swiftRange = Range(groupRange, in: text) else {
                        return nil
                    }
                    return String(text[swiftRange])
                }
            }
        }

        nonisolated private static func decodeFallbackToolCall(from raw: String) -> AIToolCall? {
            guard let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AIToolCall.self, from: data) else {
                return nil
            }
            return decoded
        }

        nonisolated private static func decodeFallbackToolCallsEnvelope(from raw: String) -> [AIToolCall]? {
            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawToolCalls = object["tool_calls"] as? [[String: Any]] else {
                return nil
            }

            let decodedToolCalls = rawToolCalls.compactMap { rawCall -> AIToolCall? in
                guard JSONSerialization.isValidJSONObject(rawCall),
                      let callData = try? JSONSerialization.data(withJSONObject: rawCall),
                      let call = try? JSONDecoder().decode(AIToolCall.self, from: callData) else {
                    return nil
                }
                return call
            }
            return decodedToolCalls.isEmpty ? nil : decodedToolCalls
        }

        nonisolated private static func extractFirstJSONCodeBlock(from content: String) -> String? {
            guard let openingRange = content.range(of: "```json") ?? content.range(of: "```") else {
                return nil
            }
            let remainder = content[openingRange.upperBound...]
            guard let closingRange = remainder.range(of: "```") else {
                return nil
            }
            return remainder[..<closingRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Unload all cached models to free memory
        func unloadAllModels() {
            synchronizeMLXStream()
            containersByModelDirectory.removeAll()
            accessOrder.removeAll()
            Memory.clearCache()
        }

        /// Unload a specific model
        func unloadModel(modelDirectory: URL) {
            synchronizeMLXStream()
            let cacheKey = modelDirectory.resolvingSymlinksInPath().standardizedFileURL
            containersByModelDirectory.removeValue(forKey: cacheKey)
            accessOrder.removeAll { $0 == cacheKey }
            Memory.clearCache()
        }

        private func loadContainerCached(modelDirectory: URL, toolCallFormat: ToolCallFormat? = nil) async throws -> ModelContainer {
            let cacheKey = modelDirectory.resolvingSymlinksInPath().standardizedFileURL
            print("[LOCAL-MLX] loadContainerCached cacheKey=\(cacheKey.path) toolCallFormat=\(String(describing: toolCallFormat))")

            // Cache hit - update LRU order
            if let existing = containersByModelDirectory[cacheKey] {
                print("[LOCAL-MLX] loadContainerCached cache hit")
                accessOrder.removeAll { $0 == cacheKey }
                accessOrder.append(cacheKey)
                return existing
            }

            // Evict oldest if at capacity
            if containersByModelDirectory.count >= maxCachedModels, let oldest = accessOrder.first {
                containersByModelDirectory.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }

            let configuration = ModelConfiguration(
                directory: cacheKey,
                toolCallFormat: toolCallFormat
            )
            let container = try await loadModelContainer(
                configuration: configuration,
                modelDirectory: cacheKey
            )
            containersByModelDirectory[cacheKey] = container
            accessOrder.append(cacheKey)
            return container
        }

        private func loadModelContainer(
            configuration: ModelConfiguration,
            modelDirectory: URL
        ) async throws -> ModelContainer {
            let useVLMFactory = try shouldUseVLMFactory(modelDirectory: modelDirectory)
            print("[LOCAL-MLX] loadModelContainer directory=\(modelDirectory.path) useVLMFactory=\(useVLMFactory)")
            if useVLMFactory {
                return try await VLMModelFactory.shared.loadContainer(configuration: configuration)
            }
            return try await MLXLMCommon.loadModelContainer(configuration: configuration)
        }

        private func shouldUseVLMFactory(modelDirectory: URL) throws -> Bool {
            let configURL = modelDirectory.appendingPathComponent("config.json")
            let configData = try Data(contentsOf: configURL)
            guard let configObject = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                print("[LOCAL-MLX] shouldUseVLMFactory invalid config object at \(configURL.path)")
                return false
            }

            let topLevelModelType = configObject["model_type"] as? String
            let nestedTextModelType = (configObject["text_config"] as? [String: Any])?["model_type"] as? String
            print("[LOCAL-MLX] shouldUseVLMFactory config=\(configURL.path) model_type=\(String(describing: topLevelModelType)) text_config.model_type=\(String(describing: nestedTextModelType))")

            if let modelType = topLevelModelType,
               modelType == "qwen3_vl" || modelType == "qwen3_5" {
                return true
            }

            if nestedTextModelType == "qwen3_5_text" {
                return true
            }

            if let processorConfigURL = [
                modelDirectory.appendingPathComponent("preprocessor_config.json"),
                modelDirectory.appendingPathComponent("processor_config.json")
            ].first(where: { FileManager.default.fileExists(atPath: $0.path) }),
               let processorData = try? Data(contentsOf: processorConfigURL),
               let processorObject = try? JSONSerialization.jsonObject(with: processorData) as? [String: Any],
               let processorClass = processorObject["processor_class"] as? String,
               processorClass == "Qwen3VLProcessor" {
                return true
            }

            return false
        }
    }

    private let selectionStore: LocalModelSelectionStore
    private let fileStore: ModelFileStoring
    private let generator: LocalModelGenerating
    private let settingsStore: any OpenRouterSettingsLoading
    private var memoryPressureObserver: (any MemoryPressureObserving)?
    private let prefixCache = PromptPrefixCache()
    private let activityCoordinator: (any AgentActivityCoordinating)?

    init(
        selectionStore: LocalModelSelectionStore = LocalModelSelectionStore(),
        fileStore: ModelFileStoring = LocalModelFileStoreAdapter(),
        generator: LocalModelGenerating? = nil,
        eventBus: EventBusProtocol? = nil,
        settingsStore: any OpenRouterSettingsLoading = OpenRouterSettingsStore(),
        memoryPressureObserverFactory: MemoryPressureObserverFactory = { callback in
            MemoryPressureObserver(onMemoryPressure: callback)
        },
        activityCoordinator: (any AgentActivityCoordinating)? = nil
    ) {
        self.selectionStore = selectionStore
        self.fileStore = fileStore
        let resolvedEventBus = eventBus ?? NoOpEventBus()
        self.generator = generator ?? NativeMLXGenerator(eventBus: resolvedEventBus)
        self.settingsStore = settingsStore
        self.memoryPressureObserver = nil
        self.activityCoordinator = activityCoordinator
        let generatorForPressureHandling = self.generator
        let prefixCacheForPressureHandling = self.prefixCache

        // Register for memory pressure notifications
        self.memoryPressureObserver = memoryPressureObserverFactory {
            Task {
                if let mlxGenerator = generatorForPressureHandling as? NativeMLXGenerator {
                    await mlxGenerator.unloadAllModels()
                }
                // Also clear prefix cache on memory pressure
                await prefixCacheForPressureHandling.clearAll()
            }
        }
    }

    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
        try await sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: request.message, mediaAttachments: request.mediaAttachments)],
            mediaAttachments: request.mediaAttachments,
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            projectRoot: request.projectRoot
        ))
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        let modelId = await selectionStore.selectedModelId()
        guard !modelId.isEmpty else {
            throw AppError.aiServiceError("No local model selected.")
        }
        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw AppError.aiServiceError("Selected local model is not recognized: \(modelId)")
        }
        guard fileStore.isModelInstalled(model) else {
            throw AppError.aiServiceError("Local model is not downloaded: \(model.displayName)")
        }

        let modelDirectory = try fileStore.runtimeModelDirectory(for: model)
        let testBudget = LocalModelTestBudget.applyIfNeeded(
            to: request,
            contextLength: LocalModelFileStore.contextLength(for: model)
        )
        let contextLength = testBudget.contextLength
        
        // Build system content for caching
        let systemContent = try buildSystemContent(tools: request.tools, mode: request.mode, stage: request.stage, projectRoot: request.projectRoot)
        
        // Check prefix cache for this conversation
        let conversationId = request.conversationId
        if let conversationId = conversationId {
            let cachedPrefix = await prefixCache.getCachedPrefix(
                conversationId: conversationId,
                modelId: modelId,
                systemPrompt: systemContent,
                tools: request.tools,
                mode: request.mode
            )
            
            if cachedPrefix != nil {
                // Cache hit - the prefix is validated and can be used
                // The actual benefit is tracking; MLX handles tokenization internally
                let stats = await prefixCache.getStatistics()
                print("[PrefixCache] Hit for conversation \(conversationId). Hit rate: \(String(format: "%.1f%%", stats.hitRate * 100))")
            }
        }
        
        let chatMessages = buildChatMessages(
            messages: testBudget.retainedMessages,
            explicitContext: request.context,
            systemContent: systemContent
        )
        
        // Convert AITool to ToolSpec for MLXLLM
        let toolSpecs = convertToToolSpec(request.tools)
        
        // TELEMETRY: Log what we're sending to the model for tool calling diagnosis
        logToolCallingTelemetry(
            modelId: modelId,
            modelToolCallFormat: model.toolCallFormat,
            toolSpecs: toolSpecs,
            systemContentLength: systemContent.count,
            messageCount: chatMessages.count
        )

        let additionalContext: [String: any Sendable]? = {
            guard model.id == "mlx-community/Qwen3.5-4B-MLX-4bit@main", toolSpecs?.isEmpty == false else { return nil }
            return ["enable_thinking": false]
        }()
        let userInput = UserInput(chat: chatMessages, tools: toolSpecs, additionalContext: additionalContext)
        
        // Wrap MLX inference with power management to prevent sleep during long generations
        let response: AIServiceResponse
        if let coordinator = activityCoordinator {
            response = try await coordinator.withActivity(type: .mlxInference) {
                try await generator.generate(
                    modelDirectory: modelDirectory,
                    userInput: userInput,
                    tools: toolSpecs,
                    toolCallFormat: model.toolCallFormat,
                    runId: request.runId,
                    contextLength: contextLength,
                    maxOutputTokens: testBudget.maxOutputTokens,
                    conversationId: conversationId
                )
            }
        } else {
            response = try await generator.generate(
                modelDirectory: modelDirectory,
                userInput: userInput,
                tools: toolSpecs,
                toolCallFormat: model.toolCallFormat,
                runId: request.runId,
                contextLength: contextLength,
                maxOutputTokens: testBudget.maxOutputTokens,
                conversationId: conversationId
            )
        }
        
        // TELEMETRY: Log what we got back from the model
        logResponseTelemetry(
            modelId: modelId,
            response: response,
            toolCount: toolSpecs?.count ?? 0
        )
        
        // Store prefix in cache for future turns
        if let conversationId = conversationId {
            await prefixCache.storePrefix(
                conversationId: conversationId,
                modelId: modelId,
                systemPrompt: systemContent,
                tools: request.tools,
                mode: request.mode
            )
        }
        
        return response
    }

    func explainCode(_ code: String) async throws -> String {
        let prompt = "Explain the following code in clear, concise terms:\n\n\(code)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: prompt,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        let prompt = "Refactor this code using the following instructions:\n\(instructions)\n\nCode:\n\(code)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: prompt,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func generateCode(_ prompt: String) async throws -> String {
        let message = "Generate code for the following request:\n\(prompt)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: message,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        let prompt = "Fix this code. Error message:\n\(error)\n\nCode:\n\(code)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: prompt,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    nonisolated private func buildChatMessages(messages: [ChatMessage], explicitContext: String?, systemContent: String) -> [Chat.Message] {
        var chatMessages: [Chat.Message] = []
        let mergedSystemContent = mergedSystemContent(
            messages: messages,
            explicitContext: explicitContext,
            systemContent: systemContent
        )

        chatMessages.append(.system(mergedSystemContent))

        for message in messages {
            switch message.role {
            case .user:
                chatMessages.append(.user(
                    message.content,
                    images: imageInputs(from: message.mediaAttachments),
                    videos: videoInputs(from: message.mediaAttachments)
                ))
            case .assistant:
                chatMessages.append(.assistant(message.content))
            case .system:
                continue
            case .tool:
                chatMessages.append(.tool(replayToolMessageContent(from: message)))
            }
        }

        return chatMessages
    }

    nonisolated private func imageInputs(from attachments: [ChatMessageMediaAttachment]) -> [UserInput.Image] {
        attachments.compactMap { attachment in
            guard attachment.kind == .image else { return nil }
            return .url(attachment.url)
        }
    }

    nonisolated private func videoInputs(from attachments: [ChatMessageMediaAttachment]) -> [UserInput.Video] {
        attachments.compactMap { attachment in
            guard attachment.kind == .video else { return nil }
            return .url(attachment.url)
        }
    }

    nonisolated private func buildRawMessages(messages: [ChatMessage], explicitContext: String?, systemContent: String) -> [Message] {
        let mergedSystemContent = mergedSystemContent(
            messages: messages,
            explicitContext: explicitContext,
            systemContent: systemContent
        )

        var rawMessages: [Message] = []
        rawMessages.append([
            "role": MessageRole.system.rawValue,
            "content": mergedSystemContent,
        ])

        for message in messages {
            if message.role == .system {
                continue
            }

            var rawMessage: Message = [
                "role": message.role.rawValue,
                "content": rawContent(for: message),
            ]

            if message.role == .assistant,
               let toolCalls = message.toolCalls,
               !toolCalls.isEmpty {
                rawMessage["tool_calls"] = toolCalls.map { toolCall in
                    [
                        "id": toolCall.id,
                        "type": "function",
                        "function": [
                            "name": toolCall.name,
                            "arguments": rawMessageValue(from: toolCall.arguments) as? [String: any Sendable] ?? [:],
                        ] as [String: any Sendable],
                    ] as [String: any Sendable]
                }
            }

            rawMessages.append(rawMessage)
        }

        return rawMessages
    }

    nonisolated private func mergedSystemContent(messages: [ChatMessage], explicitContext: String?, systemContent: String) -> String {
        let normalizedContext = explicitContext?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let historicalSystemContent = messages
            .filter { $0.role == .system }
            .map(\.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ([systemContent] + (normalizedContext.map { ["Project context:\n\($0)"] } ?? []) + historicalSystemContent)
            .joined(separator: "\n\n")
    }

    nonisolated private func rawContent(for message: ChatMessage) -> String {
        if message.role == .tool {
            return replayToolMessageContent(from: message)
        }
        return message.content
    }

    nonisolated private func rawMessageValue(from value: Any) -> (any Sendable)? {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return int
        case let int8 as Int8:
            return Int(int8)
        case let int16 as Int16:
            return Int(int16)
        case let int32 as Int32:
            return Int(int32)
        case let int64 as Int64:
            return Int(int64)
        case let uint as UInt:
            return Int(uint)
        case let double as Double:
            return double
        case let float as Float:
            return Double(float)
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return number.doubleValue
        case let dictionary as [String: Any]:
            var sendableDictionary: [String: any Sendable] = [:]
            for (key, nestedValue) in dictionary {
                if let sendableValue = rawMessageValue(from: nestedValue) {
                    sendableDictionary[key] = sendableValue
                }
            }
            return sendableDictionary
        case let array as [Any]:
            return array.compactMap { rawMessageValue(from: $0) }
        case _ as NSNull:
            return nil
        default:
            return String(describing: value)
        }
    }

    nonisolated private func replayToolMessageContent(from message: ChatMessage) -> String {
        guard let envelope = ToolExecutionEnvelope.decode(from: message.content) else {
            return message.content
        }

        if let payload = envelope.payload?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty {
            return payload
        }

        let fallback = envelope.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? message.content : fallback
    }

    private func buildSystemContent(
        tools: [AITool]?,
        mode: AIMode?,
        stage: AIRequestStage? = nil,
        projectRoot: URL?
    ) throws -> String {
        let settings = settingsStore.load(includeApiKey: false)
        return try SystemPromptAssembler().assemble(
            input: .init(
                systemPromptOverride: settings.systemPrompt,
                hasTools: tools?.isEmpty == false,
                toolPromptMode: settings.toolPromptMode,
                mode: mode,
                projectRoot: projectRoot,
                reasoningMode: settings.reasoningMode,
                stage: stage,
                includeModelReasoning: settings.reasoningMode.includesModelReasoning && stage != .tool_loop
            )
        )
    }

    private func convertToToolSpec(_ tools: [AITool]?) -> [ToolSpec]? {
        guard let tools, !tools.isEmpty else { return nil }

        return tools.map { tool in
            let sendableParameters = convertToSendable(tool.parameters)

            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": sendableParameters
                ] as [String: any Sendable]
            ] as ToolSpec
        }
    }

    private func convertToSendable(_ dictionary: [String: Any]) -> [String: any Sendable] {
        var result: [String: any Sendable] = [:]
        for (key, value) in dictionary {
            result[key] = convertValueToSsendable(value)
        }
        return result
    }

    private func convertValueToSsendable(_ value: Any) -> any Sendable {
        switch value {
        case let stringValue as String:
            return stringValue
        case let intValue as Int:
            return intValue
        case let doubleValue as Double:
            return doubleValue
        case let boolValue as Bool:
            return boolValue
        case let dictionaryValue as [String: Any]:
            return convertToSendable(dictionaryValue)
        case let arrayValue as [Any]:
            return arrayValue.map { convertValueToSsendable($0) }
        default:
            return String(describing: value)
        }
    }
    
    /// Log telemetry about what we're sending to the model for tool calling diagnosis
    private func logToolCallingTelemetry(
        modelId: String,
        modelToolCallFormat: ToolCallFormat?,
        toolSpecs: [ToolSpec]?,
        systemContentLength: Int,
        messageCount: Int
    ) {
        let toolCount = toolSpecs?.count ?? 0
        let formatDesc = modelToolCallFormat?.rawValue ?? "nil"
        
        print("[ToolCallingTelemetry] === REQUEST ===")
        print("[ToolCallingTelemetry] Model: \(modelId)")
        print("[ToolCallingTelemetry] ToolCallFormat: \(formatDesc)")
        print("[ToolCallingTelemetry] Tools provided: \(toolCount)")
        
        if let tools = toolSpecs, !tools.isEmpty {
            for (index, tool) in tools.enumerated() {
                if let function = tool["function"] as? [String: Any],
                   let name = function["name"] as? String {
                    print("[ToolCallingTelemetry]   Tool[\(index)]: \(name)")
                }
            }
        }
        
        print("[ToolCallingTelemetry] System prompt length: \(systemContentLength) chars")
        print("[ToolCallingTelemetry] Message count: \(messageCount)")
    }
    
    /// Log telemetry about what we got back from the model
    private func logResponseTelemetry(
        modelId: String,
        response: AIServiceResponse,
        toolCount: Int
    ) {
        print("[ToolCallingTelemetry] === RESPONSE ===")
        print("[ToolCallingTelemetry] Model: \(modelId)")
        
        if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
            print("[ToolCallingTelemetry] Tool calls generated: \(toolCalls.count)")
            for (index, call) in toolCalls.enumerated() {
                print("[ToolCallingTelemetry]   Call[\(index)]: \(call.name)(\(call.arguments.keys.joined(separator: ", ")))")
            }
        } else {
            print("[ToolCallingTelemetry] Tool calls generated: 0 (tools were provided: \(toolCount > 0))")
        }
        
        if let content = response.content, !content.isEmpty {
            let preview = String(content.prefix(200))
            print("[ToolCallingTelemetry] Content preview: \(preview)...")
            
            // Check for textual tool call patterns in output
            let lowered = content.lowercased()
            if lowered.contains("tool_call") || lowered.contains("toolcall") {
                print("[ToolCallingTelemetry] WARNING: Model emitted 'tool_call' text pattern but no structured calls!")
            }
            if lowered.contains("```json") {
                print("[ToolCallingTelemetry] INFO: Model emitted JSON code block")
            }
        } else {
            print("[ToolCallingTelemetry] Content: (empty)")
        }
    }
}
