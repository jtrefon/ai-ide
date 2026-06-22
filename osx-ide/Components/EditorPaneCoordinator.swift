//
//  EditorPaneCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import AppKit

/// Manages editor pane configuration and rendering
@MainActor
struct EditorPaneCoordinator {

    // MARK: - Properties

    let fileEditor: FileEditorStateManager
    let workspace: WorkspaceStateManager
    let ui: UIStateManager
    let appState: AppState

    // MARK: - Initialization

    // MARK: - Public Methods

    /// Creates an editor pane view for the specified pane ID
    func makeEditorPane(for paneID: FileEditorStateManager.PaneID) -> some View {
        let manager = (paneID == .primary) ? fileEditor.primaryPane : fileEditor.secondaryPane
        let focused = (paneID == .primary) ? fileEditor.focusedPane == .primary : fileEditor.focusedPane == .secondary

        return EditorPaneView(
            paneID: paneID,
            pane: manager,
            isFocused: focused,
            onFocus: { fileEditor.focus(paneID) },
            selectionContext: appState.selectionContext,
            inlineCompletionEngine: appState.inlineCompletionEngine,
            inlineCompletionDebugOverlayEnabled: ui.inlineCompletionDebugOverlayEnabled,
            showLineNumbers: ui.showLineNumbers,
            wordWrap: ui.wordWrap,
            minimapVisible: ui.minimapVisible,
            fontSize: ui.fontSize,
            fontFamily: ui.fontFamily
        )
    }

    /// Creates the main editor view with split panes
    func makeEditorView() -> some View {
        Group {
            if fileEditor.isSplitEditor {
                if fileEditor.splitAxis == .vertical {
                    HSplitView {
                        makeEditorPane(for: .primary)
                        makeEditorPane(for: .secondary)
                    }
                } else {
                    VSplitView {
                        makeEditorPane(for: .primary)
                        makeEditorPane(for: .secondary)
                    }
                }
            } else {
                makeEditorPane(for: .primary)
            }
        }
    }

    // MARK: - Private Components

    private struct EditorPaneView: View {
        let paneID: FileEditorStateManager.PaneID
        @ObservedObject var pane: EditorPaneStateManager
        let isFocused: Bool
        let onFocus: () -> Void
        let selectionContext: CodeSelectionContext
        let inlineCompletionEngine: InlineCompletionEngine
        let inlineCompletionDebugOverlayEnabled: Bool
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
                                Button(action: {
                                    onFocus()
                                    pane.activateTab(id: tab.id)
                                }) {
                                    HStack(spacing: 6) {
                                        Text(URL(fileURLWithPath: tab.filePath).lastPathComponent +
                                                (tab.isDirty ? " •" : ""))
                                            .lineLimit(1)

                                        Button(action: {
                                            onFocus()
                                            pane.closeTab(id: tab.id)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(height: 34)
                .background(.windowBackground)

                HStack(spacing: 0) {
                    CodeEditorView(
                        paneID: paneID,
                        text: $pane.editorContent,
                        filePath: pane.selectedFile,
                        language: pane.editorLanguage,
                        selectedRange: $pane.selectedRange,
                        selectionContext: selectionContext,
                        inlineCompletionEngine: inlineCompletionEngine,
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
            }
        }
    }
}
