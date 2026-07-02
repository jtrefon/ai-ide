import Foundation
import Combine
import MLX
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
import MLXVLM
import Tokenizers
import Darwin

protocol MemoryPressureObserving: Sendable {}

private struct LocalModelTestBudget {
    static let maximumOperationalContextLength = 65536
    static let maximumOperationalOutputTokens = 2048

    let contextLength: Int
    let retainedMessages: [ChatMessage]
    let maxOutputTokens: Int

    static func applyIfNeeded(
        to request: AIServiceHistoryRequest,
        contextLength: Int,
        launchContext: AppLaunchContext
    ) -> LocalModelTestBudget {
        guard launchContext.isTesting,
              !launchContext.productionParityHarness else {
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

        let clampedContextLength = min(contextLength, 65536)
        let retainedMessages = trimMessages(request.messages, maxMessages: 4)
        return LocalModelTestBudget(
            contextLength: clampedContextLength,
            retainedMessages: retainedMessages,
            maxOutputTokens: min(2048, max(768, clampedContextLength / 3))
        )
    }

    private static func trimMessages(_ messages: [ChatMessage], maxMessages: Int) -> [ChatMessage] {
        guard messages.count > maxMessages else { return messages }
        return Array(messages.suffix(maxMessages))
    }
}

struct LocalModelGenerationPerformanceSnapshot: Sendable {
    let modelId: String
    let inferenceConfiguration: LocalModelInferenceConfiguration
    let loadMilliseconds: Int
    let totalMilliseconds: Int
    let promptTokenCount: Int?
    let promptMilliseconds: Int?
    let promptTokensPerSecond: Double?
    let generationTokenCount: Int?
    let generationMilliseconds: Int?
    let generationTokensPerSecond: Double?
    let toolCallCount: Int
    let outputCharacterCount: Int
    let rssBeforeLoadMB: Int
    let rssAfterLoadMB: Int
    let rssAfterGenerationMB: Int
    let timestamp: Date
}

actor LocalModelGenerationPerformanceRecorder {
    static let shared = LocalModelGenerationPerformanceRecorder()

    private var snapshots: [LocalModelGenerationPerformanceSnapshot] = []
    private let maxSnapshots = 100

    func clear() {
        snapshots.removeAll()
    }

    func record(_ snapshot: LocalModelGenerationPerformanceSnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }
    }

    func latest() -> LocalModelGenerationPerformanceSnapshot? {
        snapshots.last
    }
}

/// Helper class to manage memory pressure observation with a closure callback.
/// Note: NSMemoryWarningNotification is iOS-only and does not fire on macOS.
/// This effectively keeps the model hot on macOS, which is the desired behavior
/// for local MLX inference performance.
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

    private struct DefaultSamplingParameters {
        let temperature: Float
        let topP: Float
        let repetitionPenalty: Float?
        let repetitionContextSize: Int
    }

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
        func generate(modelId: String, modelDirectory: URL, userInput: sending UserInput, tools: [ToolSpec]?, toolCallFormat: ToolCallFormat?, runId: String?, inferenceConfiguration: LocalModelInferenceConfiguration, conversationId: String?) async throws -> AIServiceResponse
    }

    final class PromptCacheEntry: @unchecked Sendable {
        var cache: [KVCache]?
        var promptTokenIds: [Int] = []
        private let lock = NSLock()

        func set(cache: [KVCache]?, tokenIds: [Int]) {
            lock.lock(); defer { lock.unlock() }
            self.cache = cache
            self.promptTokenIds = tokenIds
        }

        func get() -> (cache: [KVCache]?, tokenIds: [Int]) {
            lock.lock(); defer { lock.unlock() }
            return (cache, promptTokenIds)
        }

        func clear() {
            lock.lock(); defer { lock.unlock() }
            cache = nil
            promptTokenIds = []
            Memory.clearCache()
        }
    }

    actor NativeMLXGenerator: LocalModelGenerating {
        private let eventBus: EventBusProtocol
        private var containersByModelDirectory: [URL: ModelContainer] = [:]
        private var inFlightLoads: [URL: Task<ModelContainer, Error>] = [:]
        private var accessOrder: [URL] = []
        private let maxCachedModels = 1  // Conservative - one model at a time given memory constraints
        private var generationCount: Int = 0
        private static let mlxCacheLimitBytes = 128 * 1024 * 1024  // 128 MB Metal buffer pool cap
        private static let mlxMemoryLimitBytes = 3072 * 1024 * 1024  // 3072 MB total MLX memory cap
        private static let defaultTestingRSSLimitMB = 8 * 1024
        private static let defaultOperationalRSSLimitMB = 10 * 1024
        private var promptCacheByConversation: [String: PromptCacheEntry] = [:]

        /// Shared MLX engine for unit tests. Prevents repeated model loading and GPU memory explosion.
        nonisolated static let sharedTestGenerator: LocalModelGenerating = {
            struct NoOpEventBus: EventBusProtocol {
                func publish<E: Event>(_ event: E) {}
                func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
                    AnyCancellable {}
                }
            }
            return NativeMLXGenerator(eventBus: NoOpEventBus())
        }()

        init(eventBus: EventBusProtocol) {
            self.eventBus = eventBus
            Memory.cacheLimit = Self.mlxCacheLimitBytes
            Memory.memoryLimit = Self.mlxMemoryLimitBytes
            Task { await Self.logDeviceAndMemoryInfo() }
        }

        nonisolated static func logDeviceAndMemoryInfo() async {
            let defaultDevice = Device.defaultDevice()
            let deviceType = defaultDevice.deviceType?.rawValue ?? "unknown"
            let deviceDesc = String(describing: defaultDevice)
            let gpuInfo = GPU.deviceInfo()
            let gpuArch = gpuInfo.architecture
            let maxWorkingSetMB = Int(gpuInfo.maxRecommendedWorkingSetSize / (1024 * 1024))
            let systemMemMB = gpuInfo.memorySize / (1024 * 1024)
            let cacheLimitMB = Memory.cacheLimit / (1024 * 1024)
            let memoryLimitMB = Memory.memoryLimit / (1024 * 1024)
            await AIToolTraceLogger.shared.log(type: "mlx.device_info", data: [
                "defaultDeviceType": deviceType,
                "deviceDescription": deviceDesc,
                "gpuArchitecture": gpuArch,
                "maxRecommendedWorkingSetMB": maxWorkingSetMB,
                "systemMemoryMB": systemMemMB,
                "mlxCacheLimitMB": cacheLimitMB,
                "mlxMemoryLimitMB": memoryLimitMB
            ])
            print("[LOCAL-MLX] device_info type=\(deviceType) arch=\(gpuArch) maxWorkingSetMB=\(maxWorkingSetMB) systemMemMB=\(systemMemMB) cacheLimitMB=\(cacheLimitMB) memoryLimitMB=\(memoryLimitMB)")
        }

        deinit {
            Stream().synchronize()
            Memory.clearCache()
        }

        private func performInference<R>(_ body: @escaping @Sendable () async throws -> R) async throws -> R {
            return try await body()
        }

        func generate(modelId: String, modelDirectory: URL, userInput: sending UserInput, tools: [ToolSpec]?, toolCallFormat: ToolCallFormat? = nil, runId: String?, inferenceConfiguration: LocalModelInferenceConfiguration, conversationId: String? = nil) async throws -> AIServiceResponse {
            if Task.isCancelled {
                print("[LOCAL-MLX] generate called but Task already cancelled, bailing early")
                throw CancellationError()
            }
            let mlxStream = String(describing: StreamOrDevice.default)
            let defaultDevice = Device.defaultDevice()
            let deviceType = defaultDevice.deviceType?.rawValue ?? "unknown"
            let messageCount: Int
            switch userInput.prompt {
            case .messages(let msgs): messageCount = msgs.count
            case .chat(let msgs): messageCount = msgs.count
            case .text: messageCount = 1
            }
            let toolCount = tools?.count ?? 0
            print("[LOCAL-MLX] generate modelId=\(modelId) modelDirectory=\(modelDirectory.path) toolCallFormat=\(String(describing: toolCallFormat)) contextLength=\(inferenceConfiguration.contextLength) maxKVSize=\(inferenceConfiguration.maxKVSize) maxOutputTokens=\(inferenceConfiguration.maxOutputTokens) prefillStepSize=\(inferenceConfiguration.prefillStepSize) temperature=\(inferenceConfiguration.temperature) topP=\(inferenceConfiguration.topP) repetitionPenalty=\(String(describing: inferenceConfiguration.repetitionPenalty)) repetitionContextSize=\(inferenceConfiguration.repetitionContextSize) kvCache4Bit=\(inferenceConfiguration.kvCache4BitEnabled) stream=\(mlxStream) device=\(deviceType) messages=\(messageCount) tools=\(toolCount)")
            await AIToolTraceLogger.shared.log(type: "mlx.generate_start", data: [
                "runId": runId ?? "",
                "modelId": modelId,
                "deviceType": deviceType,
                "contextLength": inferenceConfiguration.contextLength,
                "maxKVSize": inferenceConfiguration.maxKVSize,
                "maxOutputTokens": inferenceConfiguration.maxOutputTokens,
                "prefillStepSize": inferenceConfiguration.prefillStepSize,
                "temperature": inferenceConfiguration.temperature,
                "topP": inferenceConfiguration.topP,
                "kvCache4Bit": inferenceConfiguration.kvCache4BitEnabled,
                "cacheKind": inferenceConfiguration.cacheKind,
                "messageCount": messageCount,
                "toolCount": toolCount,
                "conversationId": conversationId ?? ""
            ])
            let preparedUserInput = userInput
            let rssLimitMB = Self.resolvedRSSLimitMB()
            let generationStart = ContinuousClock.now

            let parameters = GenerateParameters(
                maxTokens: inferenceConfiguration.maxOutputTokens,
                maxKVSize: inferenceConfiguration.maxKVSize,
                kvBits: inferenceConfiguration.kvCache4BitEnabled ? 4 : nil,
                temperature: inferenceConfiguration.temperature,
                topP: inferenceConfiguration.topP,
                repetitionPenalty: inferenceConfiguration.repetitionPenalty,
                repetitionContextSize: inferenceConfiguration.repetitionContextSize,
                prefillStepSize: inferenceConfiguration.prefillStepSize
            )
            let eventBus = self.eventBus
            let cacheEntry: PromptCacheEntry? = conversationId.map { id in
                if let existing = promptCacheByConversation[id] {
                    return existing
                }
                let entry = PromptCacheEntry()
                promptCacheByConversation[id] = entry
                return entry
            }
            do {
                let response = try await performInference {
                    if Task.isCancelled {
                        throw CancellationError()
                    }
                    let rssBeforeLoadMB = Self.currentProcessRSSMB()
                    try Self.throwIfProcessRSSExceeded(limitMB: rssLimitMB, phase: "before_container_load")
                    let loadStart = ContinuousClock.now
                    let container = try await self.loadContainerCached(modelDirectory: modelDirectory, toolCallFormat: toolCallFormat)
                    let loadDuration = loadStart.duration(to: ContinuousClock.now)
                    let rssAfterLoadMB = Self.currentProcessRSSMB()
                    try Self.throwIfProcessRSSExceeded(limitMB: rssLimitMB, phase: "after_container_load")
                    let mlxActiveAfterLoad = MLX.Memory.activeMemory / (1024 * 1024)
                    let mlxPeakAfterLoad = MLX.Memory.peakMemory / (1024 * 1024)
                    print("[LOCAL-MLX] model loaded load_ms=\(Self.milliseconds(loadDuration)) rss_after_load_mb=\(rssAfterLoadMB) mlx_active=\(mlxActiveAfterLoad)MB mlx_peak=\(mlxPeakAfterLoad)MB")
                    await AIToolTraceLogger.shared.log(type: "mlx.model_loaded", data: [
                        "runId": runId ?? "",
                        "modelId": modelId,
                        "loadMs": Self.milliseconds(loadDuration),
                        "rssBeforeLoadMB": rssBeforeLoadMB,
                        "rssAfterLoadMB": rssAfterLoadMB
                    ])
                    return try await container.perform { context in
                        try Self.throwIfProcessRSSExceeded(limitMB: rssLimitMB, phase: "before_generation")

                        let input = try await context.processor.prepare(input: preparedUserInput)
                        let promptTokenCount = input.text.tokens.size
                        let promptTokenIds = input.text.tokens.asArray(Int.self)
                        print("[LOCAL-MLX] prompt prepared prompt_tokens=\(promptTokenCount)")
                        await AIToolTraceLogger.shared.log(type: "mlx.prompt_prepared", data: [
                            "runId": runId ?? "",
                            "modelId": modelId,
                            "promptTokens": promptTokenCount
                        ])

                        let (cachedCache, cachedTokenIds) = cacheEntry?.get() ?? (nil, [])
                        var kvCache: [KVCache]? = nil
                        var effectiveInput = input

                        if let cachedCache, !cachedCache.isEmpty, !cachedTokenIds.isEmpty, !promptTokenIds.isEmpty {
                            let commonLen = Self.commonPrefixLength(cachedTokenIds, promptTokenIds)
                            let trimCount = cachedTokenIds.count - commonLen

                            if commonLen > 0 {
                                var reuseCache: [KVCache] = []
                                var skipReuse = false
                                for cache in cachedCache {
                                    if let maxSize = cache.maxSize, cache.offset > maxSize {
                                        skipReuse = true
                                        break
                                    }
                                    if trimCount > 0 {
                                        _ = cache.trim(trimCount)
                                    }
                                    reuseCache.append(cache)
                                }

                                if !skipReuse, commonLen < promptTokenIds.count {
                                    let suffixTokens = Array(promptTokenIds[commonLen...])
                                    let suffixArray = MLXArray(suffixTokens).expandedDimensions(axis: 0)
                                    effectiveInput = LMInput(text: LMInput.Text(tokens: suffixArray), image: nil, video: nil)
                                    kvCache = reuseCache
                                    print("[LOCAL-MLX] KV cache reuse: cached=\(commonLen)/\(cachedTokenIds.count) suffix=\(suffixTokens.count) total=\(promptTokenIds.count)")
                                } else if !skipReuse, commonLen == promptTokenIds.count {
                                    kvCache = reuseCache
                                    print("[LOCAL-MLX] KV cache reuse: full match cached=\(commonLen) suffix=0")
                                }
                            }
                        }

                        if kvCache == nil {
                            // Clear old cache before creating new one to prevent
                            // double KV cache allocation (old + new = memory explosion)
                            if let cacheEntry {
                                cacheEntry.clear()
                            }
                            kvCache = context.model.newCache(parameters: parameters)
                        }

                        let rssBeforeGen = Self.currentProcessRSSMB()
                        let mlxActiveBeforeGen = MLX.Memory.activeMemory / (1024 * 1024)
                        let mlxPeakBeforeGen = MLX.Memory.peakMemory / (1024 * 1024)
                        let effectiveTokenCount = effectiveInput.text.tokens.size
                        print("[LOCAL-MLX] before generate rss=\(rssBeforeGen)MB mlx_active=\(mlxActiveBeforeGen)MB mlx_peak=\(mlxPeakBeforeGen)MB prompt_tokens=\(promptTokenCount) effective_tokens=\(effectiveTokenCount) prefillStep=\(parameters.prefillStepSize) maxKV=\(parameters.maxKVSize ?? -1) kvBits=\(parameters.kvBits ?? -1) cacheReuse=\(kvCache != nil && (kvCache?.first?.offset ?? 0) > 0)")
                        MLX.Memory.peakMemory = 0
                        let genStart = ContinuousClock.now
                        let stream = try MLXLMCommon.generate(
                            input: effectiveInput,
                            cache: kvCache,
                            parameters: parameters,
                            context: context
                        )

                        var output = ""
                        var collectedToolCalls: [AIToolCall] = []
                        var completionInfo: GenerateCompletionInfo?
                        var chunkCount = 0
                        var pendingChunkBuffer: [String] = []
                        var isInThinking = false
                        var thinkingCharCount = 0
                        var executionCharCount = 0
                        var thinkingEnded = false

                        func publishStatus(_ message: String) {
                            guard let runId else { return }
                            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            eventBus.publish(LocalModelStreamingStatusEvent(runId: runId, message: message))
                        }

                        for await generation in stream {
                            if Task.isCancelled {
                                print("[LOCAL-MLX] generation cancelled by Task cancellation, stopping stream")
                                throw CancellationError()
                            }
                            if chunkCount % 50 == 0 {
                                try Self.throwIfProcessRSSExceeded(limitMB: rssLimitMB, phase: "streaming")
                            }
                            chunkCount += 1
                            if chunkCount == 1 {
                                let prefillMs = Self.milliseconds(genStart.duration(to: ContinuousClock.now))
                                let rssAfterPrefill = Self.currentProcessRSSMB()
                                let mlxActiveAfterPrefill = MLX.Memory.activeMemory / (1024 * 1024)
                                let mlxPeakAfterPrefill = MLX.Memory.peakMemory / (1024 * 1024)
                                print("[LOCAL-MLX] first token generated prefill_ms=\(prefillMs) prompt_tokens=\(promptTokenCount) rss=\(rssAfterPrefill)MB mlx_active=\(mlxActiveAfterPrefill)MB mlx_peak=\(mlxPeakAfterPrefill)MB")
                                await AIToolTraceLogger.shared.log(type: "mlx.first_token", data: [
                                    "runId": runId ?? "",
                                    "modelId": modelId,
                                    "prefillMs": prefillMs,
                                    "promptTokens": promptTokenCount,
                                    "promptTokensPerSecond": promptTokenCount > 0 ? Double(promptTokenCount) / (Double(prefillMs) / 1000.0) : 0
                                ])
                            }
                            if chunkCount % 50 == 0 {
                                let elapsedMs = Self.milliseconds(genStart.duration(to: ContinuousClock.now))
                                print("[LOCAL-MLX] generation progress chunks=\(chunkCount) elapsed_ms=\(elapsedMs) output_chars=\(output.count)")
                            }

                            switch generation {
                            case .chunk(let text):
                                // Track thinking vs execution phases
                                if text.contains("<|channel>") {
                                    isInThinking = true
                                }
                                if text.contains("<channel|>") {
                                    isInThinking = false
                                    thinkingEnded = true
                                }
                                if isInThinking {
                                    thinkingCharCount += text.count
                                } else {
                                    executionCharCount += text.count
                                }
                                output.append(text)
                                if let runId, !text.isEmpty {
                                    pendingChunkBuffer.append(text)
                                    if pendingChunkBuffer.count >= 8 || chunkCount % 8 == 0 {
                                        let batch = pendingChunkBuffer.joined()
                                        pendingChunkBuffer.removeAll(keepingCapacity: true)
                                        eventBus.publish(LocalModelStreamingChunkEvent(runId: runId, chunk: batch))
                                    }
                                }
                            case .info:
                                if case .info(let info) = generation {
                                    completionInfo = info
                                }
                            case .toolCall(let toolCall):
                                collectedToolCalls.append(Self.makeAIToolCall(from: toolCall))
                                publishStatus("Structured tool call detected: \(toolCall.function.name)")
                            }
                        }
                        if !pendingChunkBuffer.isEmpty, let runId {
                            let batch = pendingChunkBuffer.joined()
                            eventBus.publish(LocalModelStreamingChunkEvent(runId: runId, chunk: batch))
                        }

                        if let cacheEntry, let kvCache, !kvCache.isEmpty {
                            let generatedIds = completionInfo?.generatedTokenIds ?? []
                            let fullTokenIds = promptTokenIds + generatedIds
                            cacheEntry.set(cache: kvCache, tokenIds: fullTokenIds)
                        }

                        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        let totalDuration = generationStart.duration(to: ContinuousClock.now)
                        let totalMs = Self.milliseconds(totalDuration)
                        let genMs: Int
                        let genTokens: Int
                        let genTps: Double
                        let promptMs: Int
                        let promptTokens: Int
                        let promptTps: Double
                        if let info = completionInfo {
                            promptMs = Int((info.promptTime * 1000).rounded())
                            promptTokens = info.promptTokenCount
                            promptTps = info.promptTokensPerSecond
                            genMs = Int((info.generateTime * 1000).rounded())
                            genTokens = info.generationTokenCount
                            genTps = info.tokensPerSecond
                        } else {
                            promptMs = 0
                            promptTokens = promptTokenCount
                            promptTps = 0
                            genMs = totalMs - Self.milliseconds(loadDuration)
                            genTokens = chunkCount
                            genTps = 0
                        }
                        await AIToolTraceLogger.shared.log(type: "mlx.generate_complete", data: [
                            "runId": runId ?? "",
                            "modelId": modelId,
                            "deviceType": deviceType,
                            "loadMs": Self.milliseconds(loadDuration),
                            "promptMs": promptMs,
                            "promptTokens": promptTokens,
                            "promptTokensPerSecond": promptTps,
                            "generationMs": genMs,
                            "generationTokens": genTokens,
                            "generationTokensPerSecond": genTps,
                            "totalMs": totalMs,
                            "outputChars": trimmedOutput.count,
                            "toolCalls": collectedToolCalls.count,
                            "chunkCount": chunkCount,
                            "rssBeforeLoadMB": rssBeforeLoadMB,
                            "rssAfterLoadMB": rssAfterLoadMB,
                            "rssAfterGenMB": Self.currentProcessRSSMB(),
                            "contextLength": inferenceConfiguration.contextLength,
                            "maxKVSize": inferenceConfiguration.maxKVSize,
                            "maxOutputTokens": inferenceConfiguration.maxOutputTokens,
                            "kvCache4Bit": inferenceConfiguration.kvCache4BitEnabled,
                            "cacheKind": inferenceConfiguration.cacheKind,
                            "hasCompletionInfo": completionInfo != nil
                        ])
                        let approxThinkingTokens = max(0, thinkingCharCount) / 4
                        let approxExecutionTokens = max(0, executionCharCount) / 4
                        print("[LOCAL-MLX-PERF] model=\(modelId) load_ms=\(Self.milliseconds(loadDuration)) prompt_ms=\(promptMs) prompt_tps=\(String(format: "%.1f", promptTps)) gen_tokens=\(genTokens) gen_ms=\(genMs) gen_tps=\(String(format: "%.1f", genTps)) total_ms=\(totalMs) context=\(inferenceConfiguration.contextLength) max_kv=\(inferenceConfiguration.maxKVSize) max_output=\(inferenceConfiguration.maxOutputTokens) prefill_step=\(inferenceConfiguration.prefillStepSize) cache_kind=\(inferenceConfiguration.cacheKind) tool_calls=\(collectedToolCalls.count) output_chars=\(trimmedOutput.count) thinking_chars=\(thinkingCharCount) execution_chars=\(executionCharCount) approx_thinking_tokens=\(approxThinkingTokens) approx_execution_tokens=\(approxExecutionTokens) thinking_ended=\(thinkingEnded) rss_before_load_mb=\(rssBeforeLoadMB) rss_after_load_mb=\(rssAfterLoadMB) rss_after_gen_mb=\(Self.currentProcessRSSMB())")
                        Self.logGenerationPerformance(
                            modelId: modelId,
                            inferenceConfiguration: inferenceConfiguration,
                            loadDuration: loadDuration,
                            totalDuration: totalDuration,
                            completionInfo: completionInfo,
                            outputCharacterCount: trimmedOutput.count,
                            toolCallCount: collectedToolCalls.count,
                            rssBeforeLoadMB: rssBeforeLoadMB,
                            rssAfterLoadMB: rssAfterLoadMB,
                            rssAfterGenerationMB: Self.currentProcessRSSMB()
                        )
                        let toolCalls: [AIToolCall]? = collectedToolCalls.isEmpty ? nil : collectedToolCalls
                        return AIServiceResponse(
                            content: trimmedOutput.isEmpty ? nil : trimmedOutput,
                            toolCalls: toolCalls
                        )
                    }
                }

                generationCount += 1
                logMLXMemorySnapshot()
                if Self.shouldUnloadModelAfterGeneration() {
                    print("[LOCAL-MLX] *** UNLOADING MODEL AFTER GENERATION (env flag set) ***")
                    unloadModel(modelDirectory: modelDirectory, reason: "post_generation_env_flag")
                }

                return response
            } catch {
                print("[LOCAL-MLX] *** UNLOADING MODEL DUE TO ERROR: \(error) ***")
                unloadModel(modelDirectory: modelDirectory, reason: "generation_error")
                throw error
            }
        }

        func preload(modelId: String, modelDirectory: URL, toolCallFormat: ToolCallFormat?) async throws {
            let loadStart = ContinuousClock.now
            _ = try await loadContainerCached(modelDirectory: modelDirectory, toolCallFormat: toolCallFormat)
            let loadDuration = loadStart.duration(to: ContinuousClock.now)
            print(
                "[LOCAL-MLX] preload modelId=\(modelId) load_ms=\(Self.milliseconds(loadDuration))"
            )
        }

        private func synchronizeMLXStream() {
            Stream().synchronize()
        }

        private func logMLXMemorySnapshot() {
            let snapshot = Memory.snapshot()
            let activeMB = snapshot.activeMemory / (1024 * 1024)
            let cacheMB = snapshot.cacheMemory / (1024 * 1024)
            let peakMB = snapshot.peakMemory / (1024 * 1024)
            print("[MLXMemory] gen=\(generationCount) active=\(activeMB)MB cache=\(cacheMB)MB peak=\(peakMB)MB")
            Task {
                await AIToolTraceLogger.shared.log(type: "mlx.memory_snapshot", data: [
                    "generationCount": generationCount,
                    "activeMB": activeMB,
                    "cacheMB": cacheMB,
                    "peakMB": peakMB
                ])
            }
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

        nonisolated private static func shouldUnloadModelAfterGeneration() -> Bool {
            let environment = ProcessInfo.processInfo.environment
            if let configured = environment["OSXIDE_LOCAL_MODEL_UNLOAD_AFTER_GENERATION"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            {
                switch configured {
                case "1", "true", "yes":
                    return true
                case "0", "false", "no":
                    return false
                default:
                    break
                }
            }

            // Keep the model hot by default, even in tests. The harness already enforces
            // a process RSS budget, and repeated cold loads dominate offline-agent latency.
            return false
        }

        nonisolated private static func logGenerationPerformance(
            modelId: String,
            inferenceConfiguration: LocalModelInferenceConfiguration,
            loadDuration: Duration,
            totalDuration: Duration,
            completionInfo: GenerateCompletionInfo?,
            outputCharacterCount: Int,
            toolCallCount: Int,
            rssBeforeLoadMB: Int,
            rssAfterLoadMB: Int,
            rssAfterGenerationMB: Int
        ) {
            let loadMS = milliseconds(loadDuration)
            let totalMS = milliseconds(totalDuration)
            let snapshot: LocalModelGenerationPerformanceSnapshot
            if let info = completionInfo {
                let promptMS = Int((info.promptTime * 1000).rounded())
                let generateMS = Int((info.generateTime * 1000).rounded())
                let promptTPS = String(format: "%.1f", info.promptTokensPerSecond)
                let generationTPS = String(format: "%.1f", info.tokensPerSecond)
                snapshot = LocalModelGenerationPerformanceSnapshot(
                    modelId: modelId,
                    inferenceConfiguration: inferenceConfiguration,
                    loadMilliseconds: loadMS,
                    totalMilliseconds: totalMS,
                    promptTokenCount: info.promptTokenCount,
                    promptMilliseconds: promptMS,
                    promptTokensPerSecond: info.promptTokensPerSecond,
                    generationTokenCount: info.generationTokenCount,
                    generationMilliseconds: generateMS,
                    generationTokensPerSecond: info.tokensPerSecond,
                    toolCallCount: toolCallCount,
                    outputCharacterCount: outputCharacterCount,
                    rssBeforeLoadMB: rssBeforeLoadMB,
                    rssAfterLoadMB: rssAfterLoadMB,
                    rssAfterGenerationMB: rssAfterGenerationMB,
                    timestamp: Date()
                )
                // PERF log moved to generate() with thinking breakdown
            } else {
                snapshot = LocalModelGenerationPerformanceSnapshot(
                    modelId: modelId,
                    inferenceConfiguration: inferenceConfiguration,
                    loadMilliseconds: loadMS,
                    totalMilliseconds: totalMS,
                    promptTokenCount: nil,
                    promptMilliseconds: nil,
                    promptTokensPerSecond: nil,
                    generationTokenCount: nil,
                    generationMilliseconds: nil,
                    generationTokensPerSecond: nil,
                    toolCallCount: toolCallCount,
                    outputCharacterCount: outputCharacterCount,
                    rssBeforeLoadMB: rssBeforeLoadMB,
                    rssAfterLoadMB: rssAfterLoadMB,
                    rssAfterGenerationMB: rssAfterGenerationMB,
                    timestamp: Date()
                )
                // PERF log moved to generate() with thinking breakdown
            }

            Task {
                await LocalModelGenerationPerformanceRecorder.shared.record(snapshot)
            }
        }

        nonisolated private static func milliseconds(_ duration: Duration) -> Int {
            Int((Double(duration.components.seconds) * 1000) + (Double(duration.components.attoseconds) / 1_000_000_000_000_000))
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
            let rawArgs = toolCall.function.arguments.mapValues { $0.anyValue }
            // Gemma 4 uses <|"|> (token id 52) as a string delimiter. The MLX
            // framework may not strip it from decoded string values, so we strip
            // it here so tools receive clean arguments.
            let arguments: [String: Any] = rawArgs.mapValues { value in
                guard var str = value as? String else { return value }
                str = str.replacingOccurrences(of: "<|\"|>", with: "")
                return str
            }
            return AIToolCall(
                id: UUID().uuidString,
                name: toolCall.function.name,
                arguments: arguments
            )
        }

        nonisolated static func commonPrefixLength(_ a: [Int], _ b: [Int]) -> Int {
            let minLen = min(a.count, b.count)
            for i in 0..<minLen {
                if a[i] != b[i] { return i }
            }
            return minLen
        }

        nonisolated static func extractGemmaToolCalls(from content: String) -> [AIToolCall]? {
            // Actual Gemma 4 format: call:name{json_args} inside <|tool_call>...<tool_call|>
            // Use a balanced brace parser instead of regex to handle deeply nested JSON.
            let calls = parseGemmaToolCalls(from: content)
            guard !calls.isEmpty else { return nil }
            return calls
        }

        nonisolated static func parseGemmaToolCalls(from content: String) -> [AIToolCall] {
            let marker = "call:"
            var results: [AIToolCall] = []
            var searchStart = content.startIndex

            while let markerRange = content.range(of: marker, range: searchStart..<content.endIndex) {
                let afterMarker = markerRange.upperBound

                // Parse tool name: \w+ characters after "call:"
                var nameEnd = afterMarker
                while nameEnd < content.endIndex, content[nameEnd].isLetter || content[nameEnd].isNumber || content[nameEnd] == "_" {
                    nameEnd = content.index(after: nameEnd)
                }
                guard nameEnd > afterMarker else {
                    searchStart = markerRange.upperBound
                    continue
                }
                let name = String(content[afterMarker..<nameEnd])

                // Skip whitespace until opening brace
                var braceStart = nameEnd
                while braceStart < content.endIndex, content[braceStart].isWhitespace {
                    braceStart = content.index(after: braceStart)
                }
                guard braceStart < content.endIndex, content[braceStart] == "{" else {
                    searchStart = nameEnd
                    continue
                }

                // Balanced brace scan to find matching closing brace
                var depth = 1
                var pos = content.index(after: braceStart)
                while pos < content.endIndex && depth > 0 {
                    let ch = content[pos]
                    if ch == "{" { depth += 1 }
                    else if ch == "}" { depth -= 1 }
                    if depth > 0 {
                        pos = content.index(after: pos)
                    }
                }
                guard depth == 0 else {
                    searchStart = nameEnd
                    continue
                }
                let argsText = String(content[content.index(after: braceStart)..<pos])

                // Gemma 4 uses <|"|> (token id 52) as a string delimiter instead of
                // regular quote characters. Replace with " so the text becomes valid JSON.
                let cleanedArgs = argsText.replacingOccurrences(of: "<|\"|>", with: "\"")

                // Try proper JSON parsing first (most reliable)
                let jsonText = "{\(cleanedArgs)}"
                var arguments: [String: Any] = [:]
                if let jsonData = jsonText.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: jsonData),
                   let argsDict = jsonObj as? [String: Any] {
                    arguments = argsDict
                } else {
                    // Fallback: parse bare key:value pairs
                    var fallbackArgs: [String: String] = [:]
                    let stripped = cleanedArgs.replacingOccurrences(of: "\"", with: "")
                    let pairPattern = #"(\w+):(.*?)(?:,\s*\w+|$)"#
                    if let pairRegex = try? NSRegularExpression(pattern: pairPattern, options: [.dotMatchesLineSeparators]) {
                        let pairRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
                        let pairMatches = pairRegex.matches(in: stripped, options: [], range: pairRange)
                        for pair in pairMatches {
                            guard pair.numberOfRanges >= 3,
                                  let keyRange = Range(pair.range(at: 1), in: stripped),
                                  let valRange = Range(pair.range(at: 2), in: stripped) else { continue }
                            let key = String(stripped[keyRange])
                            let val = String(stripped[valRange]).trimmingCharacters(in: .whitespaces)
                            fallbackArgs[key] = val
                        }
                    }
                    arguments = fallbackArgs
                }

                results.append(AIToolCall(
                    id: UUID().uuidString,
                    name: name,
                    arguments: arguments
                ))

                searchStart = content.index(after: pos)
            }

            return results
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
        func unloadAllModels(reason: String = "unknown") {
            print("[LOCAL-MLX] unloadAllModels reason=\(reason) containers=\(containersByModelDirectory.count) genCount=\(generationCount)")
            synchronizeMLXStream()
            containersByModelDirectory.removeAll()
            inFlightLoads.removeAll()
            accessOrder.removeAll()
            Memory.clearCache()
        }

        /// Unload a specific model
        func unloadModel(modelDirectory: URL, reason: String = "unknown") {
            print("[LOCAL-MLX] unloadModel reason=\(reason) path=\(modelDirectory.lastPathComponent)")
            synchronizeMLXStream()
            let cacheKey = modelDirectory.resolvingSymlinksInPath().standardizedFileURL
            containersByModelDirectory.removeValue(forKey: cacheKey)
            inFlightLoads.removeValue(forKey: cacheKey)
            accessOrder.removeAll { $0 == cacheKey }
            promptCacheByConversation.removeAll()
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

            if let existingTask = inFlightLoads[cacheKey] {
                print("[LOCAL-MLX] loadContainerCached awaiting in-flight load")
                return try await existingTask.value
            }

            // Evict oldest if at capacity
            if containersByModelDirectory.count >= maxCachedModels, let oldest = accessOrder.first {
                containersByModelDirectory.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }

            let configuration = ModelConfiguration(directory: cacheKey, toolCallFormat: toolCallFormat)
            let loadTask = Task<ModelContainer, Error> {
                try await self.loadModelContainer(
                    configuration: configuration,
                    modelDirectory: cacheKey
                )
            }
            inFlightLoads[cacheKey] = loadTask

            let container: ModelContainer
            do {
                container = try await loadTask.value
            } catch {
                inFlightLoads.removeValue(forKey: cacheKey)
                throw error
            }

            inFlightLoads.removeValue(forKey: cacheKey)
            containersByModelDirectory[cacheKey] = container
            accessOrder.append(cacheKey)
            return container
        }

        private func loadModelContainer(
            configuration _: ModelConfiguration,
            modelDirectory: URL
        ) async throws -> ModelContainer {
            let useVLMFactory = try shouldUseVLMFactory(modelDirectory: modelDirectory)
            print("[LOCAL-MLX] loadModelContainer directory=\(modelDirectory.path) useVLMFactory=\(useVLMFactory)")
            struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
                let directory: URL
                func load(from _: URL) async throws -> any MLXLMCommon.Tokenizer {
                    let upstream = try await AutoTokenizer.from(modelFolder: directory)
                    struct Bridge: MLXLMCommon.Tokenizer {
                        let upstream: any Tokenizers.Tokenizer
                        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
                            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
                        }
                        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
                            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
                        }
                        func convertTokenToId(_ token: String) -> Int? {
                            upstream.convertTokenToId(token)
                        }
                        func convertIdToToken(_ id: Int) -> String? {
                            upstream.convertIdToToken(id)
                        }
                        var bosToken: String? { upstream.bosToken }
                        var eosToken: String? { upstream.eosToken }
                        var unknownToken: String? { upstream.unknownToken }
                        func applyChatTemplate(
                            messages: [[String: any Sendable]],
                            tools: [[String: any Sendable]]?,
                            additionalContext: [String: any Sendable]?
                        ) throws -> [Int] {
                            do {
                                return try upstream.applyChatTemplate(
                                    messages: messages, tools: tools,
                                    additionalContext: additionalContext)
                            } catch Tokenizers.TokenizerError.missingChatTemplate {
                                throw MLXLMCommon.TokenizerError.missingChatTemplate
                            }
                        }
                    }
                    return Bridge(upstream: upstream)
                }
            }
            let tokenizerLoader = LocalTokenizerLoader(directory: modelDirectory)
            if useVLMFactory {
                do {
                    return try await VLMModelFactory.shared.loadContainer(
                        from: modelDirectory, using: tokenizerLoader)
                } catch {
                    print("[LOCAL-MLX] VLM loader failed for \(modelDirectory.lastPathComponent). Falling back to text-only container. error=\(error)")
                }
            }
            return try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory, using: tokenizerLoader)
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
               modelType == "qwen3_5" {
                return false
            }

            if let nestedTextModelType,
               nestedTextModelType == "qwen3_5_text" {
                return false
            }

            if let modelType = topLevelModelType,
               modelType == "qwen3_vl" {
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
    private var lifecycleObservers: [NSObjectProtocol] = []
    private let prefixCache = PromptPrefixCache()
    private let activityCoordinator: (any AgentActivityCoordinating)?
    private let launchContext: AppLaunchContext
    private var cachedTokenizer: (directory: URL, tokenizer: any Tokenizers.Tokenizer)?
    private var tokenizerLoadInFlight: Task<(URL, any Tokenizers.Tokenizer)?, Never>?

    init(
        selectionStore: LocalModelSelectionStore = LocalModelSelectionStore(),
        fileStore: ModelFileStoring = LocalModelFileStoreAdapter(),
        generator: LocalModelGenerating? = nil,
        eventBus: EventBusProtocol? = nil,
        settingsStore: any OpenRouterSettingsLoading = OpenRouterSettingsStore(),
        memoryPressureObserverFactory: MemoryPressureObserverFactory = { callback in
            MemoryPressureObserver(onMemoryPressure: callback)
        },
        activityCoordinator: (any AgentActivityCoordinating)? = nil,
        launchContext: AppLaunchContext = AppRuntimeEnvironment.launchContext
    ) {
        self.selectionStore = selectionStore
        self.fileStore = fileStore
        let resolvedEventBus = eventBus ?? NoOpEventBus()
        self.generator = generator ?? NativeMLXGenerator(eventBus: resolvedEventBus)
        self.settingsStore = settingsStore
        self.memoryPressureObserver = nil
        self.activityCoordinator = activityCoordinator
        self.launchContext = launchContext
        let generatorForPressureHandling = self.generator
        let prefixCacheForPressureHandling = self.prefixCache

        // Register for memory pressure notifications
        self.memoryPressureObserver = memoryPressureObserverFactory {
            Task {
                await AppLogger.shared.warning(
                    category: .localModel,
                    message: "memory_pressure_unload",
                    context: AppLogger.LogCallContext(metadata: [
                        "timestamp": ISO8601DateFormatter().string(from: Date())
                    ])
                )
                print("[LOCAL-MLX] *** MEMORY PRESSURE DETECTED — unloading all models ***")
                if let mlxGenerator = generatorForPressureHandling as? NativeMLXGenerator {
                    await mlxGenerator.unloadAllModels(reason: "memory_pressure")
                }
                // Also clear prefix cache on memory pressure
                await prefixCacheForPressureHandling.clearAll()
            }
        }
        if !launchContext.isTesting {
            Task {
                await registerLifecycleObservers()
                await preloadSelectedModelIfNeeded()
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
        ensureTokenizerLoaded(modelDirectory: modelDirectory)
        let storedContextLength = await selectionStore.contextLength()
        let kvCache4BitEnabled = await selectionStore.isKVCache4BitEnabled()
        let effectiveKVCache4Bit = kvCache4BitEnabled && model.supportsQuantizedKVCache
        let testBudget = LocalModelTestBudget.applyIfNeeded(
            to: request,
            contextLength: storedContextLength ?? LocalModelFileStore.contextLength(for: model),
            launchContext: launchContext
        )
        let defaultSampling = defaultSamplingParameters(
            mode: request.mode,
            stage: request.stage
        )
        let inferenceConfiguration = await LocalModelInferenceOverrides.shared.resolve(
            defaultContextLength: testBudget.contextLength,
            defaultMaxOutputTokens: testBudget.maxOutputTokens,
            defaultTemperature: defaultSampling.temperature,
            defaultTopP: defaultSampling.topP,
            defaultRepetitionPenalty: defaultSampling.repetitionPenalty,
            defaultRepetitionContextSize: defaultSampling.repetitionContextSize,
            defaultKVCache4BitEnabled: effectiveKVCache4Bit
        )
        let safeInferenceConfiguration = model.supportsQuantizedKVCache
            ? inferenceConfiguration
            : LocalModelInferenceConfiguration(
                contextLength: inferenceConfiguration.contextLength,
                maxKVSize: inferenceConfiguration.maxKVSize,
                maxOutputTokens: inferenceConfiguration.maxOutputTokens,
                prefillStepSize: inferenceConfiguration.prefillStepSize,
                temperature: inferenceConfiguration.temperature,
                topP: inferenceConfiguration.topP,
                repetitionPenalty: inferenceConfiguration.repetitionPenalty,
                repetitionContextSize: inferenceConfiguration.repetitionContextSize,
                kvCache4BitEnabled: false
            )
        let isTesting = launchContext.isTesting
        let settings = settingsStore.load(includeApiKey: false)
        
        // Build system content for caching
        let systemContent = try buildSystemContent(
            tools: request.tools,
            mode: request.mode,
            stage: request.stage,
            projectRoot: request.projectRoot,
            settings: settings
        )
        
        // Check prefix cache for this conversation
        let conversationId = request.conversationId
        if !isTesting, let conversationId = conversationId {
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
                await AppLogger.shared.debug(
                    category: .localModel,
                    message: "prefix_cache_hit",
                    context: AppLogger.LogCallContext(metadata: [
                        "conversationId": conversationId,
                        "hitRate": String(format: "%.1f%%", stats.hitRate * 100)
                    ])
                )
            }
        }
        
        let budgetedMessages = budgetMessages(
            testBudget.retainedMessages,
            explicitContext: request.context,
            systemContent: systemContent,
            inferenceConfiguration: inferenceConfiguration
        )
        let chatMessages = buildChatMessages(
            messages: budgetedMessages,
            explicitContext: request.context,
            systemContent: systemContent
        )
        
        // Convert AITool to ToolSpec for MLXLLM
        let toolSpecs = convertToToolSpec(request.tools)
        
        // TELEMETRY: Log what we're sending to the model for tool calling diagnosis
        await logToolCallingTelemetry(
            modelId: modelId,
            modelToolCallFormat: model.toolCallFormat,
            toolSpecs: toolSpecs,
            systemContentLength: systemContent.count,
            messageCount: chatMessages.count
        )
        await AIToolTraceLogger.shared.log(type: "mlx.send_message", data: [
            "runId": request.runId ?? "",
            "modelId": modelId,
            "systemPromptChars": systemContent.count,
            "systemPromptApproxTokens": approximateTokenCount(systemContent),
            "messageCount": chatMessages.count,
            "toolCount": toolSpecs?.count ?? 0,
            "mode": request.mode?.rawValue ?? "unknown",
            "stage": request.stage?.rawValue ?? "unknown",
            "contextLength": safeInferenceConfiguration.contextLength,
            "maxOutputTokens": safeInferenceConfiguration.maxOutputTokens,
            "maxKVSize": safeInferenceConfiguration.maxKVSize,
            "prefillStepSize": safeInferenceConfiguration.prefillStepSize,
            "kvCache4Bit": safeInferenceConfiguration.kvCache4BitEnabled,
            "cacheKind": safeInferenceConfiguration.cacheKind,
            "conversationId": conversationId ?? ""
        ])

        let additionalContext = additionalContext(
            for: model,
            settings: settings,
            stage: request.stage
        )
        let rawMessages = buildRawMessages(
            messages: budgetedMessages,
            explicitContext: request.context,
            systemContent: systemContent
        )
        let allImages = budgetedMessages.flatMap { message in
            imageInputs(from: message.mediaAttachments)
        }
        let allVideos = budgetedMessages.flatMap { message in
            videoInputs(from: message.mediaAttachments)
        }
        let userInput = UserInput(
            messages: rawMessages, images: allImages, videos: allVideos,
            tools: toolSpecs, additionalContext: additionalContext
        )
        
        // Wrap MLX inference with power management to prevent sleep during long generations
        let response: AIServiceResponse
        if let coordinator = activityCoordinator {
            response = try await coordinator.withActivity(type: .mlxInference) {
                try await generator.generate(
                    modelId: model.id,
                    modelDirectory: modelDirectory,
                    userInput: userInput,
                    tools: toolSpecs,
                    toolCallFormat: model.toolCallFormat,
                    runId: request.runId,
                    inferenceConfiguration: safeInferenceConfiguration,
                    conversationId: conversationId
                )
            }
        } else {
            response = try await generator.generate(
                modelId: model.id,
                modelDirectory: modelDirectory,
                userInput: userInput,
                tools: toolSpecs,
                toolCallFormat: model.toolCallFormat,
                runId: request.runId,
                inferenceConfiguration: safeInferenceConfiguration,
                conversationId: conversationId
            )
        }
        
        // TELEMETRY: Log what we got back from the model
        await logResponseTelemetry(
            modelId: modelId,
            response: response,
            toolCount: toolSpecs?.count ?? 0
        )
        
        // Store prefix in cache for future turns
        if !isTesting, let conversationId = conversationId {
            await prefixCache.storePrefix(
                conversationId: conversationId,
                modelId: modelId,
                systemPrompt: systemContent,
                tools: request.tools,
                mode: request.mode
            )
        } else if isTesting {
            await prefixCache.clearAll()
        }
        
        return response
    }

    func preloadSelectedModelIfNeeded() async {
        guard await selectionStore.isOfflineModeEnabled() else { return }
        await preloadCurrentSelection(unloadExistingModels: false)
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

            if message.role == .tool {
                let toolName = message.toolName ?? "unknown_tool"
                let toolContent = replayToolMessageContent(from: message)
                rawMessages.append([
                    "role": "tool",
                    "content": toolContent,
                    "tool_responses": [
                        [
                            "name": toolName,
                            "response": toolContent,
                        ] as [String: any Sendable],
                    ] as [any Sendable],
                ] as [String: any Sendable])
                continue
            }

            var rawMessage: Message = [
                "role": message.role.rawValue,
                "content": message.content,
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
        projectRoot: URL?,
        settings: OpenRouterSettings
    ) throws -> String {
        let systemPrompt = try SystemPromptAssembler().assemble(
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
        var prompt = systemPrompt
        if settings.reasoningMode.includesModelReasoning && stage != .tool_loop {
            prompt += "\n\n" + ReasoningIntensity.current.systemPromptDirective
        }
        return prompt + "\n\n" + localModelResponseGuidance(mode: mode, stage: stage)
    }

    private func additionalContext(
        for model: LocalModelDefinition,
        settings: OpenRouterSettings,
        stage: AIRequestStage?
    ) -> [String: any Sendable]? {
        guard model.id == "mlx-community/Qwen3.5-4B-MLX-4bit@main" else {
            return nil
        }

        let enableThinking = settings.reasoningMode.includesModelReasoning && stage != .tool_loop
        return ["enable_thinking": enableThinking]
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

    private func localModelResponseGuidance(mode: AIMode?, stage: AIRequestStage?) -> String {
        var lines = [
            "Local response guidance:",
            "- Prefer the shortest response that fully solves the request.",
            "- Do not narrate obvious steps or repeat the user's request.",
            "- When the user asks for brevity, match it exactly and stop.",
            "- For coding help, prioritize code, edits, and direct conclusions over exposition."
        ]
        if mode == .agent || stage == .tool_loop {
            lines.append("- During agent/tool work, keep status text condensed and action-oriented.")
        }
        return lines.joined(separator: "\n")
    }

    private func defaultSamplingParameters(
        mode: AIMode?,
        stage: AIRequestStage?
    ) -> DefaultSamplingParameters {
        if stage == .tool_loop || mode == .agent {
            return DefaultSamplingParameters(
                temperature: 0.2,
                topP: 0.9,
                repetitionPenalty: 1.05,
                repetitionContextSize: 64
            )
        }

        return DefaultSamplingParameters(
            temperature: 0.35,
            topP: 0.92,
            repetitionPenalty: 1.03,
            repetitionContextSize: 64
        )
    }

    private func budgetMessages(
        _ messages: [ChatMessage],
        explicitContext: String?,
        systemContent: String,
        inferenceConfiguration: LocalModelInferenceConfiguration
    ) -> [ChatMessage] {
        guard !messages.isEmpty else { return messages }

        let reservedOutputTokens = inferenceConfiguration.maxOutputTokens
        let systemTokens = approximateTokenCount(systemContent)
        let explicitContextTokens = approximateTokenCount(explicitContext ?? "")
        let overheadTokens = 256
        let availableHistoryBudget = max(
            256,
            inferenceConfiguration.contextLength - reservedOutputTokens - systemTokens - explicitContextTokens - overheadTokens
        )

        var selected: [ChatMessage] = []
        var consumedTokens = 0
        for message in messages.reversed() {
            let messageTokens = approximateTokenCount(message.content) + 16
            let mustKeep = selected.isEmpty && message.role == .user
            if !mustKeep && consumedTokens + messageTokens > availableHistoryBudget {
                continue
            }
            selected.append(message)
            consumedTokens += messageTokens
        }

        return selected.reversed()
    }

    private func approximateTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        if let cached = cachedTokenizer {
            return cached.tokenizer.encode(text: text, addSpecialTokens: false).count
        }
        return max(1, (text.count + 3) / 4)
    }

    private func ensureTokenizerLoaded(modelDirectory: URL) {
        if cachedTokenizer != nil { return }
        if tokenizerLoadInFlight != nil { return }
        let dir = modelDirectory
        tokenizerLoadInFlight = Task<(URL, any Tokenizers.Tokenizer)?, Never> {
            do {
                let tokenizer = try await AutoTokenizer.from(modelFolder: dir)
                return (dir, tokenizer)
            } catch {
                return nil
            }
        }
        Task { [weak self] in
            guard let self else { return }
            if let result = await self.tokenizerLoadInFlight?.value {
                await self.setCachedTokenizer(result.0, result.1)
            } else {
                await self.clearTokenizerLoadInFlight()
            }
        }
    }

    private func clearTokenizerLoadInFlight() {
        tokenizerLoadInFlight = nil
    }

    private func setCachedTokenizer(_ directory: URL, _ tokenizer: any Tokenizers.Tokenizer) {
        if let existing = cachedTokenizer, existing.directory == directory { return }
        cachedTokenizer = (directory, tokenizer)
        tokenizerLoadInFlight = nil
    }

    private func convertToSendable(_ dictionary: [String: Any]) -> [String: any Sendable] {
        var result: [String: any Sendable] = [:]
        for (key, value) in dictionary {
            result[key] = convertValueToSsendable(value)
        }
        return result
    }

    private func registerLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }

        let offlineObserver = NotificationCenter.default.addObserver(
            forName: .localModelOfflineModeDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            Task {
                await self.handleOfflineModeChanged(enabled: enabled)
            }
        }
        let selectionObserver = NotificationCenter.default.addObserver(
            forName: .localModelSelectionDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleSelectedModelChanged()
            }
        }
        lifecycleObservers = [offlineObserver, selectionObserver]
    }

    private func handleOfflineModeChanged(enabled: Bool) async {
        print("[LOCAL-MLX] *** OFFLINE MODE CHANGED: \(enabled) ***")
        if enabled {
            await preloadCurrentSelection(unloadExistingModels: true)
            return
        }
        if let nativeGenerator = generator as? NativeMLXGenerator {
            await nativeGenerator.unloadAllModels(reason: "offline_mode_disabled")
        }
    }

    private func handleSelectedModelChanged() async {
        guard await selectionStore.isOfflineModeEnabled() else { return }
        await preloadCurrentSelection(unloadExistingModels: true)
    }

    private func preloadCurrentSelection(unloadExistingModels: Bool) async {
        let modelId = await selectionStore.selectedModelId()
        guard !modelId.isEmpty,
              let model = LocalModelCatalog.model(id: modelId),
              fileStore.isModelInstalled(model),
              let nativeGenerator = generator as? NativeMLXGenerator else {
            return
        }

        do {
            if unloadExistingModels {
                await nativeGenerator.unloadAllModels(reason: "preload_reload")
            }
            let modelDirectory = try fileStore.runtimeModelDirectory(for: model)
            if let activityCoordinator {
                try await activityCoordinator.withActivity(type: .mlxInference) {
                    try await nativeGenerator.preload(
                        modelId: model.id,
                        modelDirectory: modelDirectory,
                        toolCallFormat: model.toolCallFormat
                    )
                }
            } else {
                try await nativeGenerator.preload(
                    modelId: model.id,
                    modelDirectory: modelDirectory,
                    toolCallFormat: model.toolCallFormat
                )
            }
        } catch {
            await AppLogger.shared.error(
                category: .localModel,
                message: "preload_failed",
                context: AppLogger.LogCallContext(metadata: [
                    "modelId": model.id,
                    "error": String(describing: error)
                ])
            )
        }
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
    ) async {
        let toolCount = toolSpecs?.count ?? 0
        let formatDesc = modelToolCallFormat?.rawValue ?? "nil"
        var toolNames: [String] = []
        if let tools = toolSpecs, !tools.isEmpty {
            for tool in tools {
                if let function = tool["function"] as? [String: Any],
                   let name = function["name"] as? String {
                    toolNames.append(name)
                }
            }
        }
        await AppLogger.shared.debug(
            category: .localModel,
            message: "tool_calling_request",
            context: AppLogger.LogCallContext(metadata: [
                "modelId": modelId,
                "toolCallFormat": formatDesc,
                "toolCount": toolCount,
                "toolNames": toolNames.joined(separator: ", "),
                "systemPromptLength": systemContentLength,
                "messageCount": messageCount
            ])
        )
    }
    
    /// Log telemetry about what we got back from the model
    private func logResponseTelemetry(
        modelId: String,
        response: AIServiceResponse,
        toolCount: Int
    ) async {
        let toolCallCount = response.toolCalls?.count ?? 0
        let toolCallNames = (response.toolCalls ?? []).map { "\($0.name)(\($0.arguments.keys.joined(separator: ", ")))" }.joined(separator: "; ")
        let contentPreview = response.content.map { String($0.prefix(200)) } ?? "(empty)"
        let hasTextToolCall = response.content?.lowercased().contains("tool_call") == true || response.content?.lowercased().contains("toolcall") == true
        let hasJsonBlock = response.content?.lowercased().contains("```json") == true
        print("[LOCAL-MLX-RESPONSE] toolCalls=\(toolCallCount) toolDetails=\(toolCallNames) contentPreview=\(contentPreview)")

        await AppLogger.shared.debug(
            category: .localModel,
            message: "tool_calling_response",
            context: AppLogger.LogCallContext(metadata: [
                "modelId": modelId,
                "toolCallsGenerated": toolCallCount,
                "toolCallDetails": toolCallNames,
                "toolsWereProvided": toolCount > 0,
                "contentPreview": contentPreview,
                "hasTextToolCallPattern": hasTextToolCall,
                "hasJsonBlock": hasJsonBlock
            ])
        )
    }
}
