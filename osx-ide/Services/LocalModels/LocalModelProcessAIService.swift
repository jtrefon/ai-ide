import Foundation
import Combine
@preconcurrency import MLXLMCommon
import MLXLLM

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
        func generate(modelDirectory: URL, prompt: String, runId: String?, contextLength: Int, conversationId: String?) async throws -> String
    }

    actor NativeMLXGenerator: LocalModelGenerating {
        private let eventBus: EventBusProtocol
        private var containersByModelDirectory: [URL: ModelContainer] = [:]
        private var accessOrder: [URL] = []
        private let maxCachedModels = 1  // Conservative - one model at a time given memory constraints

        init(eventBus: EventBusProtocol) {
            self.eventBus = eventBus
        }

        func generate(modelDirectory: URL, prompt: String, runId: String?, contextLength: Int, conversationId: String? = nil) async throws -> String {
            let container = try await loadContainerCached(modelDirectory: modelDirectory)
            let chat: [Chat.Message] = [.user(prompt)]
            let userInput = UserInput(chat: chat)

            // Calculate max output tokens - reserve ~40% of context for input, rest for output
            // Minimum 2048 for output to ensure tool calls aren't truncated
            let maxOutputTokens = max(2048, Int(Double(contextLength) * 0.6))

            // Only set maxTokens - let model use its default temperature/topP for peak performance
            let parameters = GenerateParameters(
                maxTokens: maxOutputTokens
            )
            let eventBus = self.eventBus

            return try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                let stream = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: context
                )

                var output = ""
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
                    case .toolCall:
                        break
                    }
                }
                await flushBufferedChunkIfNeeded(force: true)
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
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

        private func loadContainerCached(modelDirectory: URL) async throws -> ModelContainer {
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

            let container = try await MLXLMCommon.loadModelContainer(directory: cacheKey)
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
        let systemContent = buildSystemContent(tools: request.tools, mode: request.mode)
        
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
        
        let prompt = buildPrompt(
            messages: request.messages,
            explicitContext: request.context,
            tools: request.tools,
            mode: request.mode,
            precomputedSystemContent: systemContent
        )
        
        let output = try await generator.generate(
            modelDirectory: modelDirectory,
            prompt: prompt,
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
        
        return AIServiceResponse(content: output, toolCalls: nil)
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

    private func buildPrompt(messages: [ChatMessage], explicitContext: String?, tools: [AITool]?, mode: AIMode?, precomputedSystemContent: String? = nil) -> String {
        var sections: [String] = []

        // 1. Build system content (use precomputed if available for cache consistency)
        let systemContent = precomputedSystemContent ?? buildSystemContent(tools: tools, mode: mode)
        sections.append("System: \(systemContent)\n")

        // 2. Add explicit context if provided
        if let explicitContext, !explicitContext.isEmpty {
            sections.append("Context:\n\(explicitContext)\n")
        }

        // 3. Add conversation transcript
        let transcript = messages.map { message in
            let role: String
            switch message.role {
            case .user:
                role = "User"
            case .assistant:
                role = "Assistant"
            case .system:
                role = "System"
            case .tool:
                role = "Tool"
            }
            return "\(role): \(message.content)"
        }.joined(separator: "\n")
        sections.append(transcript)
        sections.append("Assistant:")
        return sections.joined(separator: "\n")
    }

    private func buildSystemContent(tools: [AITool]?, mode: AIMode?) -> String {
        var parts: [String] = []

        // Load custom system prompt from settings
        let settings = settingsStore.load(includeApiKey: false)

        if !settings.systemPrompt.isEmpty {
            parts.append(settings.systemPrompt)
        } else if let tools, !tools.isEmpty {
            // Use tool-awareness prompt when tools are available
            parts.append(ToolAwarenessPrompt.systemPrompt)
        } else {
            parts.append("You are a helpful, concise coding assistant.")
        }

        // Add mode-specific additions
        if let mode = mode {
            parts.append("\n\n\(mode.systemPromptAddition)")
        }

        if let reasoningPrompt = buildReasoningPromptIfNeeded(reasoningEnabled: settings.reasoningEnabled, mode: mode) {
            parts.append(reasoningPrompt)
        }

        return parts.joined(separator: "\n")
    }

    private func buildReasoningPromptIfNeeded(reasoningEnabled: Bool, mode: AIMode?) -> String? {
        guard let mode else { return nil }
        guard mode == .agent, reasoningEnabled else { return nil }

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
