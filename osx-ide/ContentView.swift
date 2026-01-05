//
//  ContentView.swift
//  osx-ide
//
//  Created by Jack Trefon on 25/08/2025.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var registry = UIRegistry.shared

    private struct EditorPaneView: View {
        @ObservedObject var pane: EditorPaneStateManager
        let isFocused: Bool
        let onFocus: () -> Void
        let selectionContext: CodeSelectionContext
        let showLineNumbers: Bool
        let wordWrap: Bool
        let fontSize: Double
        let fontFamily: String

        var body: some View {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if pane.tabs.isEmpty {
                            Text("Untitled")
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
                                        Text(URL(fileURLWithPath: tab.filePath).lastPathComponent + (tab.isDirty ? " •" : ""))
                                            .lineLimit(1)

                                        Button(action: {
                                            onFocus()
                                            pane.closeTab(id: tab.id)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
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
                .background(Color(NSColor.windowBackgroundColor))

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
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            WindowAccessor { window in
                DependencyContainer.shared.windowProvider.setWindow(window)
                appState.attachWindow(window)
                // Modern macOS v26 window styling
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.styleMask.insert(.fullSizeContentView)
                window.styleMask.insert(.unifiedTitleAndToolbar)
            }
            .frame(width: 0, height: 0)

            HSplitView {
                // Left sidebar
                // Left sidebar
                if appState.ui.isSidebarVisible, let view = registry.views(for: .sidebarLeft).first?.content {
                    view.frame(minWidth: 200, maxWidth: 300)
                }
                
                // Main content area
                HSplitView {
                    // Editor and terminal area
                    VSplitView {
                        // Main editor area
                        Group {
                            if appState.fileEditor.isSplitEditor {
                                if appState.fileEditor.splitAxis == .vertical {
                                    HSplitView {
                                        EditorPaneView(
                                            pane: appState.fileEditor.primaryPane,
                                            isFocused: appState.fileEditor.focusedPane == .primary,
                                            onFocus: { appState.fileEditor.focus(.primary) },
                                            selectionContext: appState.selectionContext,
                                            showLineNumbers: appState.showLineNumbers,
                                            wordWrap: appState.wordWrap,
                                            fontSize: appState.fontSize,
                                            fontFamily: appState.fontFamily
                                        )

                                        EditorPaneView(
                                            pane: appState.fileEditor.secondaryPane,
                                            isFocused: appState.fileEditor.focusedPane == .secondary,
                                            onFocus: { appState.fileEditor.focus(.secondary) },
                                            selectionContext: appState.selectionContext,
                                            showLineNumbers: appState.showLineNumbers,
                                            wordWrap: appState.wordWrap,
                                            fontSize: appState.fontSize,
                                            fontFamily: appState.fontFamily
                                        )
                                    }
                                } else {
                                    VSplitView {
                                        EditorPaneView(
                                            pane: appState.fileEditor.primaryPane,
                                            isFocused: appState.fileEditor.focusedPane == .primary,
                                            onFocus: { appState.fileEditor.focus(.primary) },
                                            selectionContext: appState.selectionContext,
                                            showLineNumbers: appState.showLineNumbers,
                                            wordWrap: appState.wordWrap,
                                            fontSize: appState.fontSize,
                                            fontFamily: appState.fontFamily
                                        )

                                        EditorPaneView(
                                            pane: appState.fileEditor.secondaryPane,
                                            isFocused: appState.fileEditor.focusedPane == .secondary,
                                            onFocus: { appState.fileEditor.focus(.secondary) },
                                            selectionContext: appState.selectionContext,
                                            showLineNumbers: appState.showLineNumbers,
                                            wordWrap: appState.wordWrap,
                                            fontSize: appState.fontSize,
                                            fontFamily: appState.fontFamily
                                        )
                                    }
                                }
                            } else {
                                EditorPaneView(
                                    pane: appState.fileEditor.primaryPane,
                                    isFocused: true,
                                    onFocus: { appState.fileEditor.focus(.primary) },
                                    selectionContext: appState.selectionContext,
                                    showLineNumbers: appState.showLineNumbers,
                                    wordWrap: appState.wordWrap,
                                    fontSize: appState.fontSize,
                                    fontFamily: appState.fontFamily
                                )
                            }
                        }
                        .frame(minHeight: 100)
                        
                        // Terminal panel
                        // Terminal panel
                        if appState.ui.isTerminalVisible, let view = registry.views(for: .panelBottom).first?.content {
                            view.frame(minHeight: 100)
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    
                    // AI Chat Panel
                    // AI Chat Panel
                    if appState.ui.isAIChatVisible, let view = registry.views(for: .panelRight).first?.content {
                        view.frame(minWidth: 300)
                    }
                }
            }

            IndexStatusBarView()
        }
        .background(Color.clear)
        .environment(\.font, .system(size: CGFloat(appState.ui.fontSize)))
        .preferredColorScheme(appState.selectedTheme.colorScheme)
        .accessibilityIdentifier("AppRootView")
        .accessibilityValue("theme=\(appState.selectedTheme.rawValue)")
    }
}

#Preview {
    ContentView(appState: DependencyContainer.shared.makeAppState())
}
