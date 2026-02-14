import Foundation
import Combine
import MLX
@preconcurrency import MLXLMCommon
import MLXLLM
import Tokenizers

protocol MemoryPressureObserving: Sendable {}

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
    }

    struct LocalModelFileStoreAdapter: ModelFileStoring {
        func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
            LocalModelFileStore.isModelInstalled(model)
        }

        func modelDirectory(modelId: String) throws -> URL {
            try LocalModelFileStore.modelDirectory(modelId: modelId)
        }
    }

    protocol LocalModelGenerating: Sendable {
        func generate(modelDirectory: URL, messages: sending [Chat.Message], tools: [ToolSpec]?, toolCallFormat: ToolCallFormat?, runId: String?, contextLength: Int, conversationId: String?) async throws -> AIServiceResponse
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

        func generate(modelDirectory: URL, messages: sending [Chat.Message], tools: [ToolSpec]?, toolCallFormat: ToolCallFormat? = nil, runId: String?, contextLength: Int, conversationId: String? = nil) async throws -> AIServiceResponse {
            let container = try await loadContainerCached(modelDirectory: modelDirectory, toolCallFormat: toolCallFormat)
            let userInput = UserInput(chat: messages, tools: tools)

            // Calculate max output tokens - reserve ~40% of context for input, rest for output
            // Minimum 2048 for output to ensure tool calls aren't truncated
            let maxOutputTokens = max(2048, Int(Double(contextLength) * 0.6))

            // Cap KV cache size to prevent unbounded memory growth during long conversations.
            // Uses RotatingKVCache which overwrites old entries beyond this limit.
            let maxKVSize = contextLength

            let parameters = GenerateParameters(
                maxTokens: maxOutputTokens,
                maxKVSize: maxKVSize
            )
            let eventBus = self.eventBus

            let response = try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                let stream = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: context
                )

                var output = ""
                var collectedToolCalls: [AIToolCall] = []
                var bufferedChunk = ""
                var lastFlushInstant = ContinuousClock.now
                let flushInterval = Duration.milliseconds(50)

                func flushBufferedChunkIfNeeded(force: Bool = false) async {
                    guard let runId else { return }
                    guard !bufferedChunk.isEmpty else { return }

                    let elapsed = lastFlushInstant.duration(to: ContinuousClock.now)
                    guard force || elapsed >= flushInterval else { return }

                    let chunkToPublish = bufferedChunk
                    bufferedChunk = ""
                    lastFlushInstant = ContinuousClock.now

                    await MainActor.run {
                        eventBus.publish(LocalModelStreamingChunkEvent(runId: runId, chunk: chunkToPublish))
                    }
                }

                for await generation in stream {
                    switch generation {
                    case .chunk(let text):
                        output.append(text)
                        if let runId, !text.isEmpty {
                            _ = runId
                            bufferedChunk.append(text)
                            await flushBufferedChunkIfNeeded()
                        }
                    case .info:
                        break
                    case .toolCall(let toolCall):
                        collectedToolCalls.append(Self.makeAIToolCall(from: toolCall))
                    }
                }
                await flushBufferedChunkIfNeeded(force: true)
                let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return AIServiceResponse(
                    content: trimmedOutput.isEmpty ? nil : trimmedOutput,
                    toolCalls: collectedToolCalls.isEmpty ? nil : collectedToolCalls
                )
            }

            generationCount += 1
            clearMLXCacheAfterGeneration()

            return response
        }

        private func clearMLXCacheAfterGeneration() {
            Memory.clearCache()
            if generationCount % 5 == 0 {
                let snapshot = Memory.snapshot()
                print("[MLXMemory] gen=\(generationCount) active=\(snapshot.activeMemory / (1024*1024))MB cache=\(snapshot.cacheMemory / (1024*1024))MB peak=\(snapshot.peakMemory / (1024*1024))MB")
            }
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
            containersByModelDirectory.removeAll()
            accessOrder.removeAll()
        }

        /// Unload a specific model
        func unloadModel(modelDirectory: URL) {
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
            let container = try await MLXLMCommon.loadModelContainer(configuration: configuration)
            containersByModelDirectory[cacheKey] = container
            accessOrder.append(cacheKey)
            return container
        }
    }

    private let selectionStore: LocalModelSelectionStore
    private let fileStore: ModelFileStoring
    private let generator: LocalModelGenerating
    private let settingsStore: any OpenRouterSettingsLoading
    private var memoryPressureObserver: (any MemoryPressureObserving)?
    private let prefixCache = PromptPrefixCache()

    init(
        selectionStore: LocalModelSelectionStore = LocalModelSelectionStore(),
        fileStore: ModelFileStoring = LocalModelFileStoreAdapter(),
        generator: LocalModelGenerating? = nil,
        eventBus: EventBusProtocol? = nil,
        settingsStore: any OpenRouterSettingsLoading = OpenRouterSettingsStore(),
        memoryPressureObserverFactory: MemoryPressureObserverFactory = { callback in
            MemoryPressureObserver(onMemoryPressure: callback)
        }
    ) {
        self.selectionStore = selectionStore
        self.fileStore = fileStore
        let resolvedEventBus = eventBus ?? NoOpEventBus()
        self.generator = generator ?? NativeMLXGenerator(eventBus: resolvedEventBus)
        self.settingsStore = settingsStore
        self.memoryPressureObserver = nil
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

        let modelDirectory = try fileStore.modelDirectory(modelId: model.id)
        let contextLength = LocalModelFileStore.contextLength(for: model)
        
        // Build system content for caching
        let systemContent = buildSystemContent(tools: request.tools, mode: request.mode, stage: request.stage)
        
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
            messages: request.messages,
            explicitContext: request.context,
            systemContent: systemContent
        )
        
        // Convert AITool to ToolSpec for MLXLLM
        let toolSpecs = convertToToolSpec(request.tools)
        
        let response = try await generator.generate(
            modelDirectory: modelDirectory,
            messages: chatMessages,
            tools: toolSpecs,
            toolCallFormat: model.toolCallFormat,
            runId: request.runId,
            contextLength: contextLength,
            conversationId: conversationId
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

        // 1. System message with mode-specific instructions (NOT tool prose)
        chatMessages.append(.system(systemContent))

        // 2. Inject explicit context as a system message if provided
        if let explicitContext, !explicitContext.isEmpty {
            chatMessages.append(.system("Project context:\n\(explicitContext)"))
        }

        // 3. Map conversation history preserving roles
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

    private func buildSystemContent(tools: [AITool]?, mode: AIMode?, stage: AIRequestStage? = nil) -> String {
        var parts: [String] = []

        // Load custom system prompt from settings
        let settings = settingsStore.load(includeApiKey: false)

        if !settings.systemPrompt.isEmpty {
            parts.append(settings.systemPrompt)
        } else if let tools, !tools.isEmpty {
            // Concise system prompt - tool definitions are injected by the chat template
            parts.append(ToolAwarenessPrompt.structuredToolCallingSystemPrompt)
        } else {
            parts.append("You are a helpful, concise coding assistant.")
        }

        // Add mode-specific additions
        if let mode = mode {
            parts.append("\n\n\(mode.systemPromptAddition)")
        }

        if let reasoningPrompt = buildReasoningPromptIfNeeded(reasoningEnabled: settings.reasoningEnabled, mode: mode, stage: stage) {
            parts.append(reasoningPrompt)
        }

        return parts.joined(separator: "\n")
    }

    private func buildReasoningPromptIfNeeded(reasoningEnabled: Bool, mode: AIMode?, stage: AIRequestStage? = nil) -> String? {
        guard let mode else { return nil }
        guard mode == .agent, reasoningEnabled else { return nil }
        if stage == .tool_loop { return nil }

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
    
    /// Convert AITool array to ToolSpec array for MLXLLM
    private func convertToToolSpec(_ tools: [AITool]?) -> [ToolSpec]? {
        guard let tools, !tools.isEmpty else { return nil }
        
        return tools.map { tool in
            // Convert parameters to Sendable format using JSON serialization
            let sendableParams = convertToSendable(tool.parameters)
            
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": sendableParams
                ] as [String: any Sendable]
            ] as [String: any Sendable]
        }
    }
    
    /// Recursively convert [String: Any] to [String: any Sendable]
    private func convertToSendable(_ dict: [String: Any]) -> [String: any Sendable] {
        var result: [String: any Sendable] = [:]
        for (key, value) in dict {
            result[key] = convertValueToSsendable(value)
        }
        return result
    }
    
    /// Convert Any to Sendable
    private func convertValueToSsendable(_ value: Any) -> any Sendable {
        switch value {
        case let s as String:
            return s
        case let i as Int:
            return i
        case let d as Double:
            return d
        case let b as Bool:
            return b
        case let dict as [String: Any]:
            return convertToSendable(dict)
        case let array as [Any]:
            return array.map { convertValueToSsendable($0) }
        default:
            return String(describing: value)
        }
    }
}
