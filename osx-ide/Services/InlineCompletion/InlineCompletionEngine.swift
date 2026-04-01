import Foundation

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
            let slowCount = await self.telemetryService.recentSlowCompletions()
            let decision = self.triggerPolicy.decision(
                for: snapshot,
                settings: settings,
                recentSlowCompletions: slowCount
            )
            guard decision.shouldRequest else {
                self.publish(nil, for: snapshot.paneID)
                return
            }

            let context = self.contextAssembler.buildContext(from: snapshot)
            let reduceWorkload = await self.telemetryService.shouldReduceWorkload()
            let retrievalContext = await self.retrievalLayer.retrieveContext(
                for: snapshot,
                request: context,
                settings: settings,
                reduceWorkload: reduceWorkload
            )

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
                maxSuggestionLength: settings.maxSuggestionLength,
                allowMultiline: snapshot.triggerReason == .manual && settings.multilineEnabled
            )

            do {
                guard let result = try await self.inferenceService.infer(for: request, settings: settings) else {
                    self.publish(nil, for: snapshot.paneID)
                    return
                }

                guard !Task.isCancelled else { return }
                guard self.activeRequestIDs[snapshot.paneID] == requestID else { return }

                let presentation = self.ranker.rank(result, for: request, aggressiveness: settings.aggressiveness)
                if let presentation {
                    await self.telemetryService.recordShown(presentation)
                }
                self.publish(presentation, for: snapshot.paneID)
            } catch {
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
            await telemetryService.recordCancelled()
        }
    }

    func markAccepted() {
        Task {
            await telemetryService.recordAccepted()
        }
    }

    func markDismissed() {
        Task {
            await telemetryService.recordDismissed()
        }
    }

    private func publish(
        _ presentation: InlineSuggestionPresentation?,
        for paneID: FileEditorStateManager.PaneID
    ) {
        suggestionHandlers[paneID]?(presentation)
    }
}

