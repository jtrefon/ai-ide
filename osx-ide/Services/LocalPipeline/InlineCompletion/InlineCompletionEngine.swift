import Foundation

extension Notification.Name {
    static let inlineCompletionStatusDidChange = Notification.Name("InlineCompletionStatusDidChange")
}

@MainActor
final class InlineCompletionEngine {
    typealias SuggestionHandler = @MainActor (InlineSuggestionPresentation?) -> Void
    typealias ManualTriggerHandler = @MainActor () -> Void

    private let settingsStore: InlineCompletionSettingsStore
    private let triggerPolicy: CompletionTriggerPolicy
    private let contextAssembler: CompletionContextAssembler
    private let retrievalLayer: CompletionRetrieving
    private let inferenceService: CompletionInferring
    private let ranker: SuggestionRanker
    private let telemetryService: CompletionTelemetryService

    private var suggestionHandlers: [FileEditorStateManager.PaneID: SuggestionHandler] = [:]
    private var manualTriggerHandlers: [FileEditorStateManager.PaneID: ManualTriggerHandler] = [:]
    private var activeRequestIDs: [FileEditorStateManager.PaneID: UUID] = [:]
    private var requestTasks: [FileEditorStateManager.PaneID: Task<Void, Never>] = [:]
    private var lastAcceptedSuggestions: [FileEditorStateManager.PaneID: String] = [:]
    private var lastAcceptedAt: [FileEditorStateManager.PaneID: Date] = [:]

    private let automaticAcceptanceCooldownMs: Double = 300
    private let automaticLatencyBudgetMs: Double = 5_000

    init(
        settingsStore: InlineCompletionSettingsStore,
        triggerPolicy: CompletionTriggerPolicy,
        contextAssembler: CompletionContextAssembler,
        retrievalLayer: CompletionRetrieving,
        inferenceService: CompletionInferring,
        ranker: SuggestionRanker,
        telemetryService: CompletionTelemetryService = CompletionTelemetryService()
    ) {
        self.settingsStore = settingsStore
        self.triggerPolicy = triggerPolicy
        self.contextAssembler = contextAssembler
        self.retrievalLayer = retrievalLayer
        self.inferenceService = inferenceService
        self.ranker = ranker
        self.telemetryService = telemetryService
    }

    func registerSuggestionHandler(
        for paneID: FileEditorStateManager.PaneID,
        handler: @escaping SuggestionHandler
    ) {
        suggestionHandlers[paneID] = handler
    }

    func unregisterSuggestionHandler(for paneID: FileEditorStateManager.PaneID) {
        suggestionHandlers.removeValue(forKey: paneID)
    }

    func registerManualTriggerHandler(
        for paneID: FileEditorStateManager.PaneID,
        handler: @escaping ManualTriggerHandler
    ) {
        manualTriggerHandlers[paneID] = handler
    }

    func unregisterManualTriggerHandler(for paneID: FileEditorStateManager.PaneID) {
        manualTriggerHandlers.removeValue(forKey: paneID)
    }

    func requestManualTrigger(for paneID: FileEditorStateManager.PaneID) {
        manualTriggerHandlers[paneID]?()
    }

    func requestCompletion(for snapshot: InlineCompletionEditorSnapshot) {
        requestTasks[snapshot.paneID]?.cancel()

        let requestID = UUID()
        activeRequestIDs[snapshot.paneID] = requestID
        let settings = settingsStore.load()

        requestTasks[snapshot.paneID] = Task { [weak self] in
            guard let self else { return }
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.request_received",
                context: AppLogger.LogCallContext(metadata: [
                    "paneID": String(describing: snapshot.paneID),
                    "trigger": snapshot.triggerReason.rawValue,
                    "language": snapshot.language,
                    "cursorPosition": snapshot.cursorPosition,
                    "selectionLength": snapshot.selectionLength,
                    "bufferLength": snapshot.buffer.count,
                    "routingMode": settings.routingMode.rawValue,
                    "retrievalEnabled": settings.retrievalEnabled
                ])
            )

            if snapshot.triggerReason == .automatic,
               let acceptedAt = self.lastAcceptedAt[snapshot.paneID],
               Date().timeIntervalSince(acceptedAt) * 1_000 < self.automaticAcceptanceCooldownMs {
                await AppLogger.shared.debug(
                    category: .ai,
                    message: "inline_completion.suppressed.acceptance_cooldown",
                    context: AppLogger.LogCallContext(metadata: [
                        "paneID": String(describing: snapshot.paneID),
                        "cooldownMs": self.automaticAcceptanceCooldownMs
                    ])
                )
                self.publish(nil, for: snapshot.paneID)
                return
            }

            let slowCount = await self.telemetryService.recentSlowCompletions()
            let decision = self.triggerPolicy.decision(
                for: snapshot,
                settings: settings,
                recentSlowCompletions: slowCount
            )
            guard decision.shouldRequest else {
                await AppLogger.shared.debug(
                    category: .ai,
                    message: "inline_completion.suppressed.trigger_policy",
                    context: AppLogger.LogCallContext(metadata: [
                        "paneID": String(describing: snapshot.paneID),
                        "trigger": snapshot.triggerReason.rawValue,
                        "recentSlowCompletions": slowCount
                    ])
                )
                self.publish(nil, for: snapshot.paneID)
                return
            }

            let context = self.contextAssembler.buildContext(from: snapshot)
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.context_built",
                context: AppLogger.LogCallContext(metadata: [
                    "paneID": String(describing: snapshot.paneID),
                    "prefixLength": context.prefix.count,
                    "suffixLength": context.suffix.count,
                    "symbolsCount": context.symbols.count,
                    "hasScopeSummary": context.scopeSummary != nil
                ])
            )
            let reduceWorkload = await self.telemetryService.shouldReduceWorkload()
            let retrievalContext: [String]
            if settings.retrievalEnabled {
                retrievalContext = await self.retrievalLayer.retrieveContext(
                    for: snapshot,
                    request: context,
                    settings: settings,
                    reduceWorkload: reduceWorkload
                )
            } else {
                retrievalContext = []
            }
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.retrieval_complete",
                context: AppLogger.LogCallContext(metadata: [
                    "paneID": String(describing: snapshot.paneID),
                    "retrievalEnabled": settings.retrievalEnabled,
                    "reduceWorkload": reduceWorkload,
                    "retrievalItems": retrievalContext.count
                ])
            )

            let maxSuggestionLength = settings.maxSuggestionLength
            let maxTokens = max(8, Int(Double(maxSuggestionLength) * 0.35))
            let request = InlineCompletionRequest(
                requestId: requestID,
                filePath: snapshot.filePath,
                language: snapshot.language,
                prefix: context.prefix,
                suffix: context.suffix,
                cursorPosition: snapshot.cursorPosition,
                scopeSummary: context.scopeSummary,
                symbols: context.symbols,
                retrievalContext: retrievalContext,
                triggerReason: snapshot.triggerReason,
                maxSuggestionLength: maxSuggestionLength,
                maxTokens: maxTokens,
                allowMultiline: snapshot.triggerReason == .manual && settings.multilineEnabled
            )

            do {
                await AppLogger.shared.debug(
                    category: .ai,
                    message: "inline_completion.inference_start",
                    context: AppLogger.LogCallContext(metadata: [
                        "paneID": String(describing: snapshot.paneID),
                        "requestId": requestID.uuidString,
                        "trigger": request.triggerReason.rawValue,
                        "routingMode": settings.routingMode.rawValue,
                        "allowMultiline": request.allowMultiline,
                        "maxSuggestionLength": request.maxSuggestionLength
                    ])
                )
                NotificationCenter.default.post(name: .inlineCompletionStatusDidChange, object: InlineCompletionStatus.generating)

                let result: InlineCompletionResult?
                var usedStreaming = false

                if let stream = try await self.inferenceService.inferStreaming(for: request, settings: settings) {
                    usedStreaming = true
                    var accumulated = ""
                    var streamingResult: InlineCompletionResult?
                    do {
                        for try await chunk in stream {
                            if Task.isCancelled { break }
                            accumulated.append(chunk)
                            let partial = InlineCompletionResult(
                                requestId: requestID,
                                suggestionText: accumulated,
                                confidenceScore: 0.5,
                                source: .local,
                                latencyMs: 0
                            )
                            if let candidate = self.ranker.rank(partial, for: request, aggressiveness: settings.aggressiveness) {
                                self.publish(candidate, for: snapshot.paneID)
                            }
                        }
                        if !accumulated.isEmpty {
                            streamingResult = InlineCompletionResult(
                                requestId: requestID,
                                suggestionText: accumulated,
                                confidenceScore: 0.5,
                                source: .local,
                                latencyMs: 0
                            )
                        }
                    } catch {
                        await AppLogger.shared.error(category: .ai, message: "inline_completion.stream_error", context: AppLogger.LogCallContext(metadata: ["error": String(describing: error)]))
                    }
                    result = streamingResult
                } else {
                    result = try await self.inferenceService.infer(for: request, settings: settings)
                }

                guard let result else {
                    await AppLogger.shared.debug(
                        category: .ai,
                        message: "inline_completion.inference_empty",
                        context: AppLogger.LogCallContext(metadata: [
                            "paneID": String(describing: snapshot.paneID),
                            "requestId": requestID.uuidString
                        ])
                    )
                    self.publish(nil, for: snapshot.paneID)
                    NotificationCenter.default.post(name: .inlineCompletionStatusDidChange, object: InlineCompletionStatus.noSuggestion)
                    return
                }

                guard !Task.isCancelled else { return }
                guard self.activeRequestIDs[snapshot.paneID] == requestID else { return }

                await AppLogger.shared.debug(
                    category: .ai,
                    message: "inline_completion.inference_result",
                    context: AppLogger.LogCallContext(metadata: [
                        "paneID": String(describing: snapshot.paneID),
                        "requestId": requestID.uuidString,
                        "source": result.source.rawValue,
                        "latencyMs": result.latencyMs,
                        "rawLength": result.suggestionText.count
                    ])
                )
                await self.telemetryService.recordObservedLatency(result.latencyMs)

                if !usedStreaming,
                   request.triggerReason == .automatic,
                   result.latencyMs > self.automaticLatencyBudgetMs {
                    await AppLogger.shared.debug(
                        category: .ai,
                        message: "inline_completion.suppressed.latency_budget_exceeded",
                        context: AppLogger.LogCallContext(metadata: [
                            "paneID": String(describing: snapshot.paneID),
                            "requestId": requestID.uuidString,
                            "latencyMs": result.latencyMs,
                            "budgetMs": self.automaticLatencyBudgetMs,
                            "source": result.source.rawValue
                        ])
                    )
                    self.publish(nil, for: snapshot.paneID)
                    NotificationCenter.default.post(name: .inlineCompletionStatusDidChange, object: InlineCompletionStatus.noSuggestion)
                    return
                }

                let presentation: InlineSuggestionPresentation?

                if usedStreaming {
                    presentation = InlineSuggestionPresentation(
                        requestId: result.requestId,
                        suggestionText: result.suggestionText,
                        source: result.source,
                        confidenceScore: result.confidenceScore,
                        latencyMs: result.latencyMs
                    )
                } else {
                    let evaluation = self.ranker.evaluate(result, for: request, aggressiveness: settings.aggressiveness)
                    switch evaluation {
                    case let .accepted(candidate):
                        if let lastAccepted = self.lastAcceptedSuggestions[snapshot.paneID],
                           self.normalizedTrailingPrefix(request.prefix, candidate: candidate.suggestionText).hasSuffix(self.normalizedSuggestion(lastAccepted)),
                           self.normalizedSuggestion(candidate.suggestionText) == self.normalizedSuggestion(lastAccepted) {
                            await AppLogger.shared.debug(
                                category: .ai,
                                message: "inline_completion.suppressed.repeated_after_accept",
                                context: AppLogger.LogCallContext(metadata: [
                                    "paneID": String(describing: snapshot.paneID),
                                    "requestId": requestID.uuidString,
                                    "suggestionPreview": String(candidate.suggestionText.prefix(80))
                                ])
                            )
                            presentation = nil
                        } else {
                            presentation = candidate
                        }
                    case let .rejected(reason):
                        await AppLogger.shared.debug(
                            category: .ai,
                            message: "inline_completion.rank_rejected",
                            context: AppLogger.LogCallContext(metadata: [
                                "paneID": String(describing: snapshot.paneID),
                                "requestId": requestID.uuidString,
                                "reason": reason
                            ])
                        )
                        presentation = nil
                    }
                }

                if let presentation {
                    await self.telemetryService.recordShown(presentation)
                }
                self.publish(presentation, for: snapshot.paneID)
                NotificationCenter.default.post(name: .inlineCompletionStatusDidChange, object: presentation != nil ? InlineCompletionStatus.idle : InlineCompletionStatus.noSuggestion)
            } catch {
                await AppLogger.shared.error(
                    category: .ai,
                    message: "inline_completion.inference_error",
                    context: AppLogger.LogCallContext(metadata: [
                        "paneID": String(describing: snapshot.paneID),
                        "requestId": requestID.uuidString,
                        "error": String(describing: error)
                    ])
                )
                self.publish(nil, for: snapshot.paneID)
            }
        }
    }

    func invalidate(_ paneID: FileEditorStateManager.PaneID) {
        requestTasks[paneID]?.cancel()
        requestTasks[paneID] = nil
        activeRequestIDs.removeValue(forKey: paneID)
        publish(nil, for: paneID)

        Task {
            await self.telemetryService.recordCancelled()
        }
    }

    func markAccepted(
        on paneID: FileEditorStateManager.PaneID,
        suggestionText: String?
    ) {
        if let suggestionText, !suggestionText.isEmpty {
            lastAcceptedSuggestions[paneID] = suggestionText
            lastAcceptedAt[paneID] = Date()
        }
        Task {
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.accepted",
                context: AppLogger.LogCallContext(metadata: [
                    "paneID": String(describing: paneID),
                    "suggestionPreview": String((suggestionText ?? "").prefix(80))
                ])
            )
            await self.telemetryService.recordAccepted()
        }
    }

    func markDismissed() {
        Task {
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.dismissed"
            )
            await self.telemetryService.recordDismissed()
        }
    }

    private func publish(
        _ presentation: InlineSuggestionPresentation?,
        for paneID: FileEditorStateManager.PaneID
    ) {
        Task {
            await AppLogger.shared.debug(
                category: .ai,
                message: "inline_completion.publish",
                context: AppLogger.LogCallContext(metadata: [
                    "paneID": String(describing: paneID),
                    "hasSuggestion": presentation != nil,
                    "source": presentation?.source.rawValue ?? "none",
                    "latencyMs": presentation?.latencyMs ?? -1,
                    "suggestionPreview": String((presentation?.suggestionText ?? "").prefix(80))
                ])
            )
        }
        suggestionHandlers[paneID]?(presentation)
    }

    private func normalizedSuggestion(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTrailingPrefix(_ prefix: String, candidate: String) -> String {
        let candidateLength = max(candidate.count * 2, 64)
        let trailingPrefix = String(prefix.suffix(candidateLength))
        return normalizedSuggestion(trailingPrefix)
    }
}
