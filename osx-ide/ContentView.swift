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
    @State private var showErrorAlert: Bool = false
    @StateObject private var selectionContext = CodeSelectionContext()
    
    var body: some View {
        VStack(spacing: 0) {
            WindowAccessor { window in
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            .frame(width: 0, height: 0)

            HSplitView {
                // Left sidebar
                FileExplorerView(appState: appState)
                    .frame(minWidth: 200, maxWidth: 300)
                
                // Main content area
                HSplitView {
                    // Editor and terminal area
                    VSplitView {
                        // Main editor area
                        VStack(spacing: 0) {
                            // Editor header
                            HStack {
                                HStack {
                                    let fileName = appState.fileEditorService.displayName
                                    let fileExtension = (fileName as NSString).pathExtension
                                    let language = AppState.languageForFileExtension(fileExtension)
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
                                selectionContext: selectionContext
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minHeight: 100)
                        
                        // Terminal panel
                        NativeTerminalView(currentDirectory: appState.currentDirectory)
                            .frame(minHeight: 100)
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    
                    // AI Chat Panel
                    AIChatPanel(
                        selectionContext: selectionContext,
                        conversationManager: appState.conversationManager
                    )
                    .frame(minWidth: 300)
                }
            }
        }
        .nativeGlassBackground(.panel)
    }
}

#Preview {
    ContentView(appState: DependencyContainer.shared.makeAppState())
}
