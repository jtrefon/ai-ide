import Foundation
import AppKit

@MainActor
final class SnippetCompletionService {
    typealias SnippetHandler = @MainActor (CodeEditorTextView) -> Void

    private let inferenceService: CompletionInferring
    private let contextAssembler: CompletionContextAssembler
    private let retrievalLayer: CompletionRetrieving
    private let ranker: SuggestionRanker
    private let telemetryService: CompletionTelemetryService

    private var activeTask: Task<Void, Never>?
    private var previewState: SnippetPreviewState?
    private var paneHandlers: [FileEditorStateManager.PaneID: SnippetHandler] = [:]

    struct SnippetPreviewState {
        let originalText: String
        let originalSelectedRange: NSRange
        let insertedRange: NSRange
        let suggestionText: String
    }

    init(
        inferenceService: CompletionInferring,
        contextAssembler: CompletionContextAssembler = CompletionContextAssembler(),
        retrievalLayer: CompletionRetrieving,
        ranker: SuggestionRanker = SuggestionRanker(),
        telemetryService: CompletionTelemetryService = CompletionTelemetryService()
    ) {
        self.inferenceService = inferenceService
        self.contextAssembler = contextAssembler
        self.retrievalLayer = retrievalLayer
        self.ranker = ranker
        self.telemetryService = telemetryService
    }

    func registerSnippetTrigger(for paneID: FileEditorStateManager.PaneID, handler: @escaping SnippetHandler) {
        paneHandlers[paneID] = handler
    }

    func unregisterSnippetTrigger(for paneID: FileEditorStateManager.PaneID) {
        paneHandlers.removeValue(forKey: paneID)
    }

    func requestSnippet(for paneID: FileEditorStateManager.PaneID) {
        guard let handler = paneHandlers[paneID] else { return }
        // Cancel any active generation first
        activeTask?.cancel()
        activeTask = nil
    }

    func requestSnippet(
        for snapshot: InlineCompletionEditorSnapshot,
        textView: CodeEditorTextView
    ) {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let context = contextAssembler.buildContext(from: snapshot)
                let settings = InlineCompletionSettings.default
                let reduction = await telemetryService.shouldReduceWorkload()
                let retrieval = await retrievalLayer.retrieveContext(
                    for: snapshot, request: context,
                    settings: settings, reduceWorkload: reduction
                )

                let request = InlineCompletionRequest(
                    requestId: UUID(),
                    filePath: snapshot.filePath,
                    language: snapshot.language,
                    prefix: context.prefix,
                    suffix: context.suffix,
                    cursorPosition: snapshot.cursorPosition,
                    scopeSummary: context.scopeSummary,
                    symbols: context.symbols,
                    retrievalContext: retrieval,
                    triggerReason: .manual,
                    maxSuggestionLength: 400,
                    maxTokens: 128,
                    allowMultiline: true
                )

                guard !Task.isCancelled else { return }

                guard let result = try await inferenceService.infer(for: request, settings: settings) else {
                    await self.telemetryService.recordCancelled()
                    return
                }

                guard let presentation = ranker.rank(result, for: request, aggressiveness: 0.8) else {
                    await self.telemetryService.recordCancelled()
                    return
                }
                guard !Task.isCancelled else { return }

                await self.applyPreview(presentation: presentation, textView: textView)
            } catch {
                await AppLogger.shared.error(
                    category: .ai,
                    message: "snippet_completion.inference_error",
                    context: AppLogger.LogCallContext(metadata: [
                        "error": String(describing: error)
                    ])
                )
            }
        }
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

    func invalidate(textView: CodeEditorTextView) {
        activeTask?.cancel()
        activeTask = nil
        if previewState != nil {
            rejectSnippet(textView: textView)
        }
    }

    var hasActivePreview: Bool {
        previewState != nil
    }

    private func applyPreview(
        presentation: InlineSuggestionPresentation,
        textView: CodeEditorTextView
    ) async {
        if let state = previewState {
            textView.textStorage?.replaceCharacters(in: state.insertedRange, with: "")
            previewState = nil
        }

        let suggestion = presentation.suggestionText
        guard !suggestion.isEmpty else { return }

        let cursor = textView.selectedRange.location
        let insertedRange = NSRange(location: cursor, length: suggestion.count)

        previewState = SnippetPreviewState(
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

        await telemetryService.recordShown(presentation)
    }
}
