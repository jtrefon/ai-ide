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
    @ObservedObject private var registry = UIRegistry.shared
    
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
                        VStack(spacing: 0) {
                            // Editor header
                            HStack {
                                HStack {
                                    let fileName = appState.fileEditor.displayName
                                    let fileExtension = (fileName as NSString).pathExtension
                                    let _ = FileEditorStateManager.languageForFileExtension(fileExtension)
                                    Text(fileName + (appState.fileEditor.isDirty ? " •" : ""))
                                        .font(.headline)
                                        .padding(.horizontal)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .frame(height: 30)
                            .background(Color(NSColor.windowBackgroundColor))
                            
                            // Code editor
                            CodeEditorView(
                                text: $appState.fileEditor.editorContent,
                                language: appState.fileEditor.editorLanguage,
                                selectedRange: $selectedRange,
                                selectionContext: appState.selectionContext,
                                showLineNumbers: appState.showLineNumbers,
                                wordWrap: appState.wordWrap,
                                fontSize: appState.fontSize,
                                fontFamily: appState.fontFamily
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
