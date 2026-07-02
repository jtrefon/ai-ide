import SwiftUI
import Markdown

struct EditorPaneView: View {
    let paneID: FileEditorStateManager.PaneID
    @ObservedObject var pane: EditorPaneStateManager
    let isFocused: Bool
    let onFocus: () -> Void
    let selectionContext: CodeSelectionContext
    let inlineCompletionEngine: InlineCompletionEngine
    let snippetCompletionService: SnippetCompletionService
    let inlineCompletionDebugOverlayEnabled: Bool
    let showLineNumbers: Bool
    let wordWrap: Bool
    let minimapVisible: Bool
    let fontSize: Double
    let fontFamily: String

    private var isMarkdownView: Bool {
        guard pane.markdownViewMode else { return false }
        guard let filePath = pane.selectedFile else { return false }
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBar(
                tabs: pane.tabs,
                activeTabID: pane.activeTabID,
                onActivate: { pane.activateTab(id: $0) },
                onClose: { pane.closeTab(id: $0) },
                onFocus: onFocus
            )

            if isMarkdownView {
                markdownPreview
            } else {
                editorContent
            }
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        ScrollView {
            MarkdownView(
                markdown: pane.editorContent,
                fontSize: fontSize,
                fontFamily: fontFamily
            ) { code, language in
                CodePreviewView(
                    code: code,
                    language: language,
                    title: language?.capitalized ?? "Code",
                    fontSize: fontSize,
                    fontFamily: fontFamily
                )
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(isFocused ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
    }

    private var editorContent: some View {
        HStack(spacing: 0) {
            CodeEditorView(
                paneID: paneID,
                text: $pane.editorContent,
                filePath: pane.selectedFile,
                language: pane.editorLanguage,
                selectedRange: $pane.selectedRange,
                selectionContext: selectionContext,
                inlineCompletionEngine: inlineCompletionEngine,
                snippetCompletionService: snippetCompletionService,
                inlineCompletionDebugOverlayEnabled: inlineCompletionDebugOverlayEnabled,
                showLineNumbers: showLineNumbers,
                wordWrap: wordWrap,
                fontSize: fontSize,
                fontFamily: fontFamily
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .stroke(isFocused ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onFocus()
            }

            if minimapVisible {
                Divider()
                MinimapView(
                    text: $pane.editorContent,
                    selectedRange: $pane.selectedRange,
                    fontFamily: fontFamily
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
