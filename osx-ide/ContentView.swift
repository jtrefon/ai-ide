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
                                let fileName = appState.selectedFile ?? "Untitled"
                                let fileExtension = (fileName as NSString).pathExtension
                                let language = AppState.languageForFileExtension(fileExtension)
                                Text(fileName + (appState.isDirty ? " •" : ""))
                                    .font(.headline)
                                    .padding(.horizontal)
                                Spacer()
                            }
                            .frame(height: 30)
                            .background(Color(NSColor.controlBackgroundColor))
                            
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
                        TerminalView()
                            .frame(minHeight: 100)
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    
                    // AI Chat Panel
                    AIChatPanel(
                        selectionContext: selectionContext
                    )
                    .frame(minWidth: 300)
                }
            }
            
            if let error = appState.lastError {
                HStack {
                    Text("Error: \(error)")
                        .foregroundColor(.white)
                        .padding(.leading)
                    Spacer()
                    Button("Dismiss") {
                        appState.lastError = nil
                    }
                    .padding(.trailing)
                    .keyboardShortcut(.defaultAction)
                }
                .frame(height: 30)
                .background(Color.red)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.default, value: appState.lastError)
            }
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}

