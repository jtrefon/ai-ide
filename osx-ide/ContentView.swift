//
//  ContentView.swift
//  osx-ide
//
//  Created by Jack Trefon on 25/08/2025.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var selectedRange: NSRange? = nil
    @StateObject private var selectionContext = CodeSelectionContext()
    
    var body: some View {
        VStack(spacing: 0) {
            WindowAccessor { window in
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

            AutosavingHSplitView(autosaveName: "MainSplit", orientation: .horizontal) {
                // Left sidebar
                FileExplorerView(appState: appState)
                    .frame(minWidth: 200, maxWidth: 300)
            } secondary: {
                // Main content area
                AutosavingHSplitView(autosaveName: "EditorChatSplit", orientation: .horizontal) {
                    // Editor and terminal area
                    AutosavingVSplitView(autosaveName: "EditorTerminalSplit", orientation: .vertical) {
                        // Main editor area
                        VStack(spacing: 0) {
                            // Editor header
                            HStack {
                                HStack {
                                    let fileName = appState.displayName
                                    let fileExtension = (fileName as NSString).pathExtension
                                    let _ = AppState.languageForFileExtension(fileExtension)
                                    Text(fileName + (appState.isDirty ? " •" : ""))
                                        .font(.headline)
                                        .padding(.horizontal)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .frame(height: 30)
                            .nativeGlassBackground(.header)
                            
                            // Code editor
                            CodeEditorView(
                                text: $appState.editorContent,
                                language: appState.editorLanguage,
                                selectedRange: $selectedRange,
                                selectionContext: selectionContext,
                                showLineNumbers: appState.showLineNumbers
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minHeight: 100)
                    } secondary: {
                        // Terminal panel
                        NativeTerminalView(currentDirectory: appState.currentDirectory)
                            .frame(minHeight: 100)
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                } secondary: {
                    // AI Chat Panel
                    AIChatPanel(
                        selectionContext: selectionContext,
                        conversationManager: appState.conversationManager
                    )
                    .frame(minWidth: 300)
                }
            }
        }
        .background(Color.clear)
    }
}

#Preview {
    ContentView(appState: DependencyContainer.shared.makeAppState())
}
