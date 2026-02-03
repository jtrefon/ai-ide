import SwiftUI
import AppKit

struct EditorPaneView: View {
    @ObservedObject var pane: EditorPaneStateManager
    let isFocused: Bool
    let onFocus: () -> Void
    let selectionContext: CodeSelectionContext
    let showLineNumbers: Bool
    let wordWrap: Bool
    let minimapVisible: Bool
    let fontSize: Double
    let fontFamily: String

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if pane.tabs.isEmpty {
                        Text(localized("editor.untitled"))
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(pane.tabs) { tab in
                            let isActive = tab.id == pane.activeTabID
                            Button(
                                action: {
                                    onFocus()
                                    pane.activateTab(id: tab.id)
                                },
                                label: {
                                    HStack(spacing: 6) {
                                        Text(
                                            URL(fileURLWithPath: tab.filePath).lastPathComponent
                                                + (tab.isDirty ? " •" : "")
                                        )
                                        .lineLimit(1)

                                        Button(
                                            action: {
                                                onFocus()
                                                pane.closeTab(id: tab.id)
                                            },
                                            label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(.secondary)
                                            }
                                        )
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                    .cornerRadius(6)
                                }
                            )
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 34)
            .background(Color(NSColor.windowBackgroundColor))

            HStack(spacing: 0) {
                CodeEditorView(
                    text: $pane.editorContent,
                    language: pane.editorLanguage,
                    selectedRange: $pane.selectedRange,
                    selectionContext: selectionContext,
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
            .background(Color(NSColor.textBackgroundColor))
        }
    }
}
