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
}

@MainActor
final class AIServiceInlineCompletionProvider: InlineCompletionProviding {
    private let aiServiceProvider: () -> AIService?
    private let remoteServiceProvider: (@Sendable () async -> AIService?)?
    private let localServiceProvider: (@Sendable () async -> AIService?)?
    private let offlineModeChecker: OfflineModeChecking
    private let localModelSelectionStore: LocalModelSelectionStore?

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
        guard let service else {
            return nil
        }

        let text = try await service.generateCode(prompt)
        return (text, source)
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
        let prompt = makePrompt(for: request)
        guard let response = try await provider.complete(
            prompt: prompt,
            triggerReason: request.triggerReason,
            routingMode: settings.routingMode
        ) else {
            return nil
        }

        return InlineCompletionResult(
            requestId: request.requestId,
            suggestionText: response.text,
            confidenceScore: 0.5,
            source: response.source,
            latencyMs: Date().timeIntervalSince(startedAt) * 1_000
        )
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
