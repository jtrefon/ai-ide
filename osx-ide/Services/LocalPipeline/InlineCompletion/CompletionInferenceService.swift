import Foundation

protocol OfflineModeChecking: Sendable {
    func isOfflineModeEnabled() async -> Bool
}

extension LocalModelSelectionStore: OfflineModeChecking {}

@MainActor
protocol InlineCompletionProviding {
    func complete(
        prompt: String,
        triggerReason: CompletionTriggerReason,
        routingMode: InlineCompletionRoutingMode
    ) async throws -> (text: String, source: InlineCompletionSource)?

    func completeLocally(
        prefix: String,
        suffix: String,
        maxTokens: Int
    ) async throws -> (text: String, source: InlineCompletionSource)?
}

@MainActor
final class AIServiceInlineCompletionProvider: InlineCompletionProviding {
    private let aiServiceProvider: () -> AIService?
    private let remoteServiceProvider: (@Sendable () async -> AIService?)?
    private let localServiceProvider: (@Sendable () async -> AIService?)?
    private let offlineModeChecker: OfflineModeChecking
    private let localModelSelectionStore: LocalModelSelectionStore?
    private var fimService: FIMInferenceService?

    init(
        aiServiceProvider: @escaping () -> AIService?,
        offlineModeChecker: OfflineModeChecking = LocalModelSelectionStore()
    ) {
        self.aiServiceProvider = aiServiceProvider
        self.remoteServiceProvider = nil
        self.localServiceProvider = nil
        self.offlineModeChecker = offlineModeChecker
        self.localModelSelectionStore = nil
    }

    init(
        remoteServiceProvider: @escaping @Sendable () async -> AIService?,
        localServiceProvider: @escaping @Sendable () async -> AIService?,
        localModelSelectionStore: LocalModelSelectionStore,
        offlineModeChecker: OfflineModeChecking? = nil
    ) {
        self.aiServiceProvider = { nil }
        self.remoteServiceProvider = remoteServiceProvider
        self.localServiceProvider = localServiceProvider
        self.localModelSelectionStore = localModelSelectionStore
        self.offlineModeChecker = offlineModeChecker ?? localModelSelectionStore
    }

    func complete(
        prompt: String,
        triggerReason: CompletionTriggerReason,
        routingMode: InlineCompletionRoutingMode
    ) async throws -> (text: String, source: InlineCompletionSource)? {
        let offlineMode = await offlineModeChecker.isOfflineModeEnabled()
        let hasLocalModel = if let localModelSelectionStore {
            !(await localModelSelectionStore.selectedModelId().trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty
        } else {
            offlineMode
        }

        await AppLogger.shared.debug(
            category: .ai,
            message: "inline_completion.provider_route",
            context: AppLogger.LogCallContext(metadata: [
                "trigger": triggerReason.rawValue,
                "routingMode": routingMode.rawValue,
                "offlineMode": offlineMode,
                "hasLocalModel": hasLocalModel
            ])
        )

        if let localServiceProvider, let remoteServiceProvider {
            if offlineMode {
                guard hasLocalModel else { return nil }
                return try await completeWith(service: await localServiceProvider(), source: .local, prompt: prompt)
            }

            switch routingMode {
            case .localOnly:
                guard hasLocalModel else { return nil }
                return try await completeWith(service: await localServiceProvider(), source: .local, prompt: prompt)
            case .remoteOnly:
                return try await completeWith(service: await remoteServiceProvider(), source: .remote, prompt: prompt)
            case .hybridPreferLocal:
                if hasLocalModel,
                   let localResult = try await attemptCompletion(
                        with: await localServiceProvider(),
                        source: .local,
                        prompt: prompt
                   ) {
                    return localResult
                }
                return try await completeWith(service: await remoteServiceProvider(), source: .remote, prompt: prompt)
            case .hybridPreferRemote:
                if let remoteResult = try await attemptCompletion(
                    with: await remoteServiceProvider(),
                    source: .remote,
                    prompt: prompt
                ) {
                    return remoteResult
                }
                guard hasLocalModel else { return nil }
                return try await completeWith(service: await localServiceProvider(), source: .local, prompt: prompt)
            }
        }

        if triggerReason == .automatic && routingMode == .localOnly && !offlineMode {
            return nil
        }

        let source: InlineCompletionSource = offlineMode ? .local : {
            switch routingMode {
            case .localOnly:
                return .local
            case .remoteOnly:
                return .remote
            case .hybridPreferLocal, .hybridPreferRemote:
                return .hybrid
            }
        }()

        return try await completeWith(service: aiServiceProvider(), source: source, prompt: prompt)
    }

    private func attemptCompletion(
        with service: AIService?,
        source: InlineCompletionSource,
        prompt: String
    ) async throws -> (text: String, source: InlineCompletionSource)? {
        do {
            return try await completeWith(service: service, source: source, prompt: prompt)
        } catch {
            await AppLogger.shared.warning(
                category: .ai,
                message: "inline_completion.provider_attempt_failed",
                context: AppLogger.LogCallContext(metadata: [
                    "source": source.rawValue,
                    "error": String(describing: error)
                ])
            )
            return nil
        }
    }

    private func completeWith(
        service: AIService?,
        source: InlineCompletionSource,
        prompt: String
    ) async throws -> (text: String, source: InlineCompletionSource)? {
        guard let service else { return nil }

        let text = try await service.generateCode(prompt)
        return (text, source)
    }

    func completeLocally(
        prefix: String,
        suffix: String,
        maxTokens: Int
    ) async throws -> (text: String, source: InlineCompletionSource)? {
        let modelId: String
        if let localModelSelectionStore {
            let stored = await localModelSelectionStore.completionModelId()
            modelId = stored.isEmpty ? LocalModelCatalog.fastFimModel.id : stored
        } else {
            modelId = LocalModelCatalog.fastFimModel.id
        }

        guard let model = LocalModelCatalog.model(id: modelId) else {
            await AppLogger.shared.warning(
                category: .ai,
                message: "inline_completion.fim_model_not_in_catalog",
                context: AppLogger.LogCallContext(metadata: ["modelId": modelId])
            )
            return nil
        }

        guard LocalModelFileStore.isModelInstalled(model) else {
            await AppLogger.shared.warning(
                category: .ai,
                message: "inline_completion.fim_model_not_installed",
                context: AppLogger.LogCallContext(metadata: [
                    "modelId": modelId,
                    "displayName": model.displayName
                ])
            )
            return nil
        }

        do {
            let service = try await resolveFIMService(modelId: modelId)
            let text = try await service.generate(prefix: prefix, suffix: suffix, maxTokens: maxTokens)
            guard !text.isEmpty else { return nil }
            return (text, .local)
        } catch {
            await AppLogger.shared.warning(
                category: .ai,
                message: "inline_completion.fim_generation_error",
                context: AppLogger.LogCallContext(metadata: [
                    "modelId": modelId,
                    "error": String(describing: error)
                ])
            )
            return nil
        }
    }

    private func resolveFIMService(modelId: String) async throws -> FIMInferenceService {
        if let existing = fimService, existing.modelId == modelId {
            return existing
        }
        let service = try await FIMInferenceService(modelId: modelId)
        fimService = service
        return service
    }
}

@MainActor
protocol CompletionInferring {
    func infer(
        for request: InlineCompletionRequest,
        settings: InlineCompletionSettings
    ) async throws -> InlineCompletionResult?
}

@MainActor
final class CompletionInferenceService: CompletionInferring {
    private let provider: InlineCompletionProviding

    init(provider: InlineCompletionProviding) {
        self.provider = provider
    }

    func infer(
        for request: InlineCompletionRequest,
        settings: InlineCompletionSettings
    ) async throws -> InlineCompletionResult? {
        let startedAt = Date()

        let source: InlineCompletionSource
        let text: String

        let result: (text: String, source: InlineCompletionSource)? = try await routeInference(
            for: request, settings: settings
        )

        guard let result else { return nil }
        text = result.text; source = result.source

        return InlineCompletionResult(
            requestId: request.requestId,
            suggestionText: text,
            confidenceScore: 0.5,
            source: source,
            latencyMs: Date().timeIntervalSince(startedAt) * 1_000
        )
    }

    private func routeInference(
        for request: InlineCompletionRequest,
        settings: InlineCompletionSettings
    ) async throws -> (text: String, source: InlineCompletionSource)? {
        switch settings.routingMode {
        case .localOnly:
            return try await attemptLocal(request: request)

        case .remoteOnly:
            return try await attemptRemote(request: request)

        case .hybridPreferLocal:
            if let local = try? await attemptLocal(request: request) {
                return local
            }
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.local_failed_falling_back_remote",
                context: AppLogger.LogCallContext(metadata: [
                    "requestId": request.requestId.uuidString
                ])
            )
            return try await attemptRemote(request: request)

        case .hybridPreferRemote:
            if let remote = try? await attemptRemote(request: request) {
                return remote
            }
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.remote_failed_falling_back_local",
                context: AppLogger.LogCallContext(metadata: [
                    "requestId": request.requestId.uuidString
                ])
            )
            return try await attemptLocal(request: request)
        }
    }

    private func attemptLocal(request: InlineCompletionRequest) async throws -> (text: String, source: InlineCompletionSource)? {
        do {
            guard let result = try await provider.completeLocally(
                prefix: request.prefix, suffix: request.suffix, maxTokens: request.maxSuggestionLength
            ) else { return nil }
            return result
        } catch {
            await AppLogger.shared.warning(
                category: .ai,
                message: "inline_completion.local_inference_error",
                context: AppLogger.LogCallContext(metadata: [
                    "requestId": request.requestId.uuidString,
                    "error": String(describing: error),
                    "language": request.language
                ])
            )
            return nil
        }
    }

    private func attemptRemote(request: InlineCompletionRequest) async throws -> (text: String, source: InlineCompletionSource)? {
        do {
            let prompt = makePrompt(for: request)
            guard let result = try await provider.complete(prompt: prompt, triggerReason: request.triggerReason, routingMode: .remoteOnly) else {
                return nil
            }
            return result
        } catch {
            await AppLogger.shared.warning(
                category: .ai,
                message: "inline_completion.remote_inference_error",
                context: AppLogger.LogCallContext(metadata: [
                    "requestId": request.requestId.uuidString,
                    "error": String(describing: error),
                    "language": request.language
                ])
            )
            return nil
        }
    }

    private func makePrompt(for request: InlineCompletionRequest) -> String {
        var parts: [String] = [
            "You are generating inline code completion for a native macOS IDE.",
            "Return only the code that should be inserted at the cursor.",
            "Do not explain. Do not use markdown. Prefer a short, likely continuation."
        ]

        parts.append("Language: \(request.language)")
        if let filePath = request.filePath {
            parts.append("File: \(filePath)")
        }
        if let scopeSummary = request.scopeSummary {
            parts.append("Scope: \(scopeSummary)")
        }
        if !request.symbols.isEmpty {
            parts.append("Nearby symbols: \(request.symbols.joined(separator: ", "))")
        }
        if !request.retrievalContext.isEmpty {
            parts.append("Retrieved context:\n\(request.retrievalContext.joined(separator: "\n"))")
        }

        parts.append("Before cursor:\n\(request.prefix)")
        parts.append("After cursor:\n\(request.suffix)")
        parts.append("Constraints: max \(request.maxSuggestionLength) characters; multiline \(request.allowMultiline ? "allowed" : "disallowed").")
        return parts.joined(separator: "\n\n")
    }
}
