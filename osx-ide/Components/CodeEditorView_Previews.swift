import SwiftUI

struct CodeEditorView_Previews: PreviewProvider {
    @MainActor
    private static var previewInlineCompletionEngine: InlineCompletionEngine {
        InlineCompletionEngine(
            settingsStore: InlineCompletionSettingsStore(),
            triggerPolicy: CompletionTriggerPolicy(),
            contextAssembler: CompletionContextAssembler(),
            retrievalLayer: CompletionRetrievalLayer(projectRootProvider: { nil }, codebaseIndexProvider: { nil }),
            inferenceService: CompletionInferenceService(provider: AIServiceInlineCompletionProvider(aiServiceProvider: { nil })),
            ranker: SuggestionRanker()
        )
    }

    @MainActor
    static var previews: some View {
        CodeEditorView(
            paneID: .primary,
            text: .constant("func helloWorld() {\n    print(\"Hello, World!\")\n}"),
            filePath: nil,
            language: "swift",
            selectedRange: .constant(nil),
            selectionContext: CodeSelectionContext(),
            inlineCompletionEngine: previewInlineCompletionEngine,
            snippetCompletionService: SnippetCompletionService(
                inferenceService: CompletionInferenceService(
                    provider: AIServiceInlineCompletionProvider(aiServiceProvider: { nil })
                ),
                retrievalLayer: CompletionRetrievalLayer(
                    projectRootProvider: { nil },
                    codebaseIndexProvider: { nil }
                )
            ),
            inlineCompletionDebugOverlayEnabled: true,
            showLineNumbers: true,
            wordWrap: false,
            fontSize: AppConstantsEditor.defaultFontSize,
            fontFamily: AppConstantsEditor.defaultFontFamily
        )
        .frame(height: 300)
    }
}
