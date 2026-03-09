import Foundation
import Combine
import MLX
@preconcurrency import MLXLMCommon
import MLXLLM
import MLXVLM
import Tokenizers

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
        func generate(modelDirectory: URL, messages: sending [Chat.Message], tools: [ToolSpec]?, toolCallFormat: ToolCallFormat?, runId: String?, contextLength: Int, maxOutputTokens: Int, conversationId: String?) async throws -> AIServiceResponse
    }

    actor NativeMLXGenerator: LocalModelGenerating {
        private let eventBus: EventBusProtocol
        private var containersByModelDirectory: [URL: ModelContainer] = [:]
        private var accessOrder: [URL] = []
        private let maxCachedModels = 1  // Conservative - one model at a time given memory constraints
        private var generationCount: Int = 0
        private static let mlxCacheLimitBytes = 256 * 1024 * 1024  // 256 MB Metal buffer pool cap

        init(eventBus: EventBusProtocol) {
            self.eventBus = eventBus
            Memory.cacheLimit = Self.mlxCacheLimitBytes
        }

        private func performInference<R>(_ body: @escaping @Sendable () async throws -> R) async throws -> R {
            return try await body()
        }

        func generate(modelDirectory: URL, messages: sending [Chat.Message], tools: [ToolSpec]?, toolCallFormat: ToolCallFormat? = nil, runId: String?, contextLength: Int, maxOutputTokens: Int, conversationId: String? = nil) async throws -> AIServiceResponse {
            let userInput = UserInput(chat: messages, tools: tools)

            // Cap KV cache size to prevent unbounded memory growth during long conversations.
            // Uses RotatingKVCache which overwrites old entries beyond this limit.
            let maxKVSize = contextLength

            let parameters = GenerateParameters(
                maxTokens: maxOutputTokens,
                maxKVSize: maxKVSize
            )
            let eventBus = self.eventBus

            let response = try await performInference {
                let container = try await self.loadContainerCached(modelDirectory: modelDirectory, toolCallFormat: toolCallFormat)
                return try await container.perform { context in
                    let input = try await context.processor.prepare(input: userInput)
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
                        switch generation {
                        case .chunk(let text):
                            output.append(text)
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
                    return AIServiceResponse(
                        content: trimmedOutput.isEmpty ? nil : trimmedOutput,
                        toolCalls: collectedToolCalls.isEmpty ? nil : collectedToolCalls
                    )
                }
            }

            synchronizeMLXStream()
            generationCount += 1
            clearMLXCacheAfterGeneration()

            return response
        }

        private func synchronizeMLXStream() {
            Stream().synchronize()
        }

        private func clearMLXCacheAfterGeneration() {
            synchronizeMLXStream()
            Memory.clearCache()
            // DIAGNOSTIC: Log memory on every generation to track growth
            let snapshot = Memory.snapshot()
            print("[MLXMemory] gen=\(generationCount) active=\(snapshot.activeMemory / (1024*1024))MB cache=\(snapshot.cacheMemory / (1024*1024))MB peak=\(snapshot.peakMemory / (1024*1024))MB")
        }

        nonisolated private static func makeAIToolCall(from toolCall: ToolCall) -> AIToolCall {
            let arguments = toolCall.function.arguments.mapValues { $0.anyValue }
            return AIToolCall(
                id: UUID().uuidString,
                name: toolCall.function.name,
                arguments: arguments
            )
        }

        /// Unload all cached models to free memory
        func unloadAllModels() {
            synchronizeMLXStream()
            containersByModelDirectory.removeAll()
            accessOrder.removeAll()
        }

        /// Unload a specific model
        func unloadModel(modelDirectory: URL) {
            synchronizeMLXStream()
            let cacheKey = modelDirectory.resolvingSymlinksInPath().standardizedFileURL
            containersByModelDirectory.removeValue(forKey: cacheKey)
            accessOrder.removeAll { $0 == cacheKey }
        }

        private func loadContainerCached(modelDirectory: URL, toolCallFormat: ToolCallFormat? = nil) async throws -> ModelContainer {
            let cacheKey = modelDirectory.resolvingSymlinksInPath().standardizedFileURL

            // Cache hit - update LRU order
            if let existing = containersByModelDirectory[cacheKey] {
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
            if try shouldUseVLMFactory(modelDirectory: modelDirectory) {
                return try await VLMModelFactory.shared.loadContainer(configuration: configuration)
            }
            return try await MLXLMCommon.loadModelContainer(configuration: configuration)
        }

        private func shouldUseVLMFactory(modelDirectory: URL) throws -> Bool {
            let configURL = modelDirectory.appendingPathComponent("config.json")
            let configData = try Data(contentsOf: configURL)
            guard let configObject = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                return false
            }

            if let modelType = configObject["model_type"] as? String,
               modelType == "qwen3_vl" || modelType == "qwen3_5" {
                return true
            }

            if let textConfig = configObject["text_config"] as? [String: Any],
               textConfig["model_type"] as? String == "qwen3_5_text" {
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
            messages: [ChatMessage(role: .user, content: request.message)],
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
        
        // Wrap MLX inference with power management to prevent sleep during long generations
        let response: AIServiceResponse
        if let coordinator = activityCoordinator {
            response = try await coordinator.withActivity(type: .mlxInference) {
                try await generator.generate(
                    modelDirectory: modelDirectory,
                    messages: chatMessages,
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
                messages: chatMessages,
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

        chatMessages.append(.system(systemContent))

        if let explicitContext, !explicitContext.isEmpty {
            chatMessages.append(.system("Project context:\n\(explicitContext)"))
        }

        for message in messages {
            switch message.role {
            case .user:
                chatMessages.append(.user(message.content))
            case .assistant:
                chatMessages.append(.assistant(message.content))
            case .system:
                chatMessages.append(.system(message.content))
            case .tool:
                chatMessages.append(.tool(message.content))
            }
        }

        return chatMessages
    }

    private func buildSystemContent(
        tools: [AITool]?,
        mode: AIMode?,
        stage: AIRequestStage? = nil,
        projectRoot: URL?
    ) throws -> String {
        var parts: [String] = []

        let settings = settingsStore.load(includeApiKey: false)

        if !settings.systemPrompt.isEmpty {
            parts.append(settings.systemPrompt)
        } else if let tools, !tools.isEmpty {
            parts.append(ToolAwarenessPrompt.structuredToolCallingSystemPrompt)
        } else {
            parts.append("You are a helpful, concise coding assistant.")
        }

        if let mode = mode {
            parts.append("\n\n\(mode.systemPromptAddition)")
        }

        if let modelReasoningPrompt = try buildModelReasoningPrompt(
            reasoningMode: settings.reasoningMode,
            projectRoot: projectRoot
        ) {
            parts.append(modelReasoningPrompt)
        }

        if let reasoningPrompt = try AIRequestStage.reasoningPromptIfNeeded(
            reasoningMode: settings.reasoningMode,
            mode: mode,
            stage: stage,
            projectRoot: projectRoot
        ) {
            parts.append(reasoningPrompt)
        }

        return parts.joined(separator: "\n")
    }

    private func buildModelReasoningPrompt(
        reasoningMode: ReasoningMode,
        projectRoot: URL?
    ) throws -> String? {
        try PromptRepository.shared.prompt(
            key: reasoningMode.modelReasoningPromptKey,
            projectRoot: projectRoot
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
        let formatDesc = modelToolCallFormat != nil ? "json" : "nil"
        
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
