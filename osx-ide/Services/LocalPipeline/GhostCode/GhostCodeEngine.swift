import Foundation
import AppKit

extension Notification.Name {
    static let ghostCodeStatusDidChange = Notification.Name("GhostCodeStatusDidChange")
}

@MainActor
final class GhostCodeEngine {
    typealias GhostCodeHandler = @MainActor (InlineSuggestionPresentation?) -> Void

    private let inferenceService: CompletionInferring
    private let contextAssembler: GhostCodeContextAssembler
    private let retrievalLayer: CompletionRetrieving
    private let ranker: GhostCodeRanker
    private let resultCache: GhostCodeResultCache
    private let telemetryService: CompletionTelemetryService
    private let triggerPolicy: GhostCodeTriggerPolicy

    private var suggestionHandlers: [FileEditorStateManager.PaneID: GhostCodeHandler] = [:]
    private var activeRequestIDs: [FileEditorStateManager.PaneID: UUID] = [:]
    private var requestTasks: [FileEditorStateManager.PaneID: Task<Void, Never>] = [:]
    private var previewState: GhostCodePreviewState?
    private var idleDetectTasks: [FileEditorStateManager.PaneID: Task<Void, Never>] = [:]
    private var manualTriggerHandlers: [FileEditorStateManager.PaneID: @MainActor () -> Void] = [:]

    struct GhostCodePreviewState {
        let originalText: String
        let originalSelectedRange: NSRange
        let insertedRange: NSRange
        let suggestionText: String
    }

    var hasActivePreview: Bool { previewState != nil }

    init(
        inferenceService: CompletionInferring,
        contextAssembler: GhostCodeContextAssembler = GhostCodeContextAssembler(),
        retrievalLayer: CompletionRetrieving,
        ranker: GhostCodeRanker = GhostCodeRanker(),
        resultCache: GhostCodeResultCache = GhostCodeResultCache(),
        telemetryService: CompletionTelemetryService = CompletionTelemetryService(),
        triggerPolicy: GhostCodeTriggerPolicy = GhostCodeTriggerPolicy()
    ) {
        self.inferenceService = inferenceService
        self.contextAssembler = contextAssembler
        self.retrievalLayer = retrievalLayer
        self.ranker = ranker
        self.resultCache = resultCache
        self.telemetryService = telemetryService
        self.triggerPolicy = triggerPolicy
    }

    func registerSuggestionHandler(for paneID: FileEditorStateManager.PaneID, handler: @escaping GhostCodeHandler) {
        suggestionHandlers[paneID] = handler
    }

    func unregisterSuggestionHandler(for paneID: FileEditorStateManager.PaneID) {
        suggestionHandlers.removeValue(forKey: paneID)
    }

    func scheduleIdleDetection(for snapshot: InlineCompletionEditorSnapshot) {
        idleDetectTasks[snapshot.paneID]?.cancel()
        idleDetectTasks[snapshot.paneID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.triggerPolicy.shouldAutoTrigger(for: snapshot, idleMs: 400) else { return }
            self.requestGhostCode(for: snapshot, textView: nil)
        }
    }

    func requestGhostCode(for snapshot: InlineCompletionEditorSnapshot, textView: CodeEditorTextView?) {
        requestTasks[snapshot.paneID]?.cancel()

        guard triggerPolicy.shouldManualTrigger(for: snapshot) else { return }

        let requestID = UUID()
        activeRequestIDs[snapshot.paneID] = requestID

        requestTasks[snapshot.paneID] = Task { [weak self] in
            guard let self else { return }

            if let cached = await self.resultCache.lookup(prefix: snapshot.buffer.prefix(snapshot.cursorPosition).suffix(200).description, suffix: snapshot.buffer.dropFirst(snapshot.cursorPosition).prefix(200).description) {
                self.publish(cached, for: snapshot.paneID)
                return
            }

            let context = self.contextAssembler.buildContext(from: snapshot)
            let settings = InlineCompletionSettings.default
            let reduceWorkload = await self.telemetryService.shouldReduceWorkload()
            let retrieval: [String]
            if settings.retrievalEnabled {
                retrieval = await self.retrievalLayer.retrieveContext(
                    for: snapshot, request: context,
                    settings: settings, reduceWorkload: reduceWorkload
                )
            } else {
                retrieval = []
            }

            let request = InlineCompletionRequest(
                requestId: requestID,
                filePath: snapshot.filePath,
                language: snapshot.language,
                prefix: context.prefix,
                suffix: context.suffix,
                cursorPosition: snapshot.cursorPosition,
                scopeSummary: context.scopeSummary,
                symbols: context.symbols,
                retrievalContext: retrieval,
                triggerReason: snapshot.triggerReason,
                maxSuggestionLength: 400,
                maxTokens: 96,
                allowMultiline: true
            )

            do {
                NotificationCenter.default.post(name: .ghostCodeStatusDidChange, object: InlineCompletionStatus.generating)

                let result = try await self.inferenceService.infer(for: request, settings: settings)

                guard let result else {
                    self.publish(nil, for: snapshot.paneID)
                    NotificationCenter.default.post(name: .ghostCodeStatusDidChange, object: InlineCompletionStatus.noSuggestion)
                    return
                }

                guard !Task.isCancelled, self.activeRequestIDs[snapshot.paneID] == requestID else { return }

                await self.telemetryService.recordObservedLatency(result.latencyMs)

                switch self.ranker.evaluate(result, for: request, aggressiveness: 0.8) {
                case .accepted(let candidate):
                    await self.telemetryService.recordShown(candidate)
                    await self.resultCache.store(candidate, prefix: context.prefix, suffix: context.suffix)
                    self.publish(candidate, for: snapshot.paneID)
                case .rejected:
                    self.publish(nil, for: snapshot.paneID)
                }

                NotificationCenter.default.post(name: .ghostCodeStatusDidChange, object: InlineCompletionStatus.idle)
            } catch {
                self.publish(nil, for: snapshot.paneID)
            }
        }
    }

    func applyPreview(presentation: InlineSuggestionPresentation, textView: CodeEditorTextView) {
        if let state = previewState {
            textView.textStorage?.replaceCharacters(in: state.insertedRange, with: "")
            previewState = nil
        }

        let suggestion = presentation.suggestionText
        guard !suggestion.isEmpty else { return }

        let cursor = textView.selectedRange.location
        let insertedRange = NSRange(location: cursor, length: suggestion.count)

        previewState = GhostCodePreviewState(
            originalText: textView.string,
            originalSelectedRange: textView.selectedRange,
            insertedRange: insertedRange,
            suggestionText: suggestion
        )

        textView.snippetPreviewInProgress = true
        textView.insertText(suggestion, replacementRange: textView.selectedRange)
        textView.snippetPreviewInProgress = false

        let highlightColor = NSColor.systemBlue.withAlphaComponent(0.15)
        let highlightRange = NSRange(location: cursor, length: suggestion.count)
        textView.textStorage?.addAttributes(
            [.backgroundColor: highlightColor],
            range: highlightRange
        )
    }

    @discardableResult
    func acceptSnippet(textView: CodeEditorTextView) -> Bool {
        guard let state = previewState else { return false }
        textView.textStorage?.addAttributes(
            [.backgroundColor: NSColor.clear],
            range: state.insertedRange
        )
        previewState = nil
        Task { await telemetryService.recordAccepted() }
        return true
    }

    func rejectSnippet(textView: CodeEditorTextView) {
        guard let state = previewState else { return }
        textView.textStorage?.replaceCharacters(in: state.insertedRange, with: "")
        textView.setSelectedRange(state.originalSelectedRange)
        previewState = nil
        Task { await telemetryService.recordDismissed() }
    }

    func invalidate(textView: CodeEditorTextView?) {
        for (_, task) in requestTasks { task.cancel() }
        requestTasks.removeAll()
        activeRequestIDs.removeAll()
        for (_, task) in idleDetectTasks { task.cancel() }
        idleDetectTasks.removeAll()
        if let textView, previewState != nil {
            rejectSnippet(textView: textView)
        }
        publish(nil, for: .primary)
    }

    func requestManualTrigger(for paneID: FileEditorStateManager.PaneID) {
        if let handler = manualTriggerHandlers[paneID] {
            handler()
        }
    }

    func registerManualTriggerHandler(for paneID: FileEditorStateManager.PaneID, handler: @escaping @MainActor () -> Void) {
        manualTriggerHandlers[paneID] = handler
    }

    func unregisterManualTriggerHandler(for paneID: FileEditorStateManager.PaneID) {
        manualTriggerHandlers.removeValue(forKey: paneID)
    }

    func invalidate(paneID: FileEditorStateManager.PaneID) {
        requestTasks[paneID]?.cancel()
        requestTasks[paneID] = nil
        activeRequestIDs.removeValue(forKey: paneID)
        idleDetectTasks[paneID]?.cancel()
        idleDetectTasks[paneID] = nil
        publish(nil, for: paneID)
    }

    private func publish(_ presentation: InlineSuggestionPresentation?, for paneID: FileEditorStateManager.PaneID) {
        suggestionHandlers[paneID]?(presentation)
    }
}
