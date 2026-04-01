import Foundation

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
    private let localModelSelectionStore: LocalModelSelectionStore

    init(
        aiServiceProvider: @escaping () -> AIService?,
        localModelSelectionStore: LocalModelSelectionStore = LocalModelSelectionStore()
    ) {
        self.aiServiceProvider = aiServiceProvider
        self.localModelSelectionStore = localModelSelectionStore
    }

    func complete(
        prompt: String,
        triggerReason: CompletionTriggerReason,
        routingMode: InlineCompletionRoutingMode
    ) async throws -> (text: String, source: InlineCompletionSource)? {
        let offlineMode = await localModelSelectionStore.isOfflineModeEnabled()

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

        guard let aiService = aiServiceProvider() else {
            return nil
        }

        let text = try await aiService.generateCode(prompt)
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
