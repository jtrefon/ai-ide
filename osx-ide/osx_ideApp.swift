//
//  osx_ideApp.swift
//  osx-ide
//
//  Created by Jack Trefon on 25/08/2025.
//

import SwiftUI

@main
struct osx_ideApp: App {
    @StateObject private var appState: AppState
    @StateObject private var errorManager: ErrorManager
    
    init() {
        let container = DependencyContainer.shared
        let errorMgr = container.errorManager
        let appSt = container.makeAppState()
        
        self._errorManager = StateObject(wrappedValue: errorMgr)
        self._appState = StateObject(wrappedValue: appSt)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .environmentObject(errorManager)
                .alert("Error", isPresented: $errorManager.showErrorAlert) {
                    Button("OK") {
                        errorManager.dismissError()
                    }
                } message: {
                    if let error = errorManager.currentError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error.localizedDescription)
                                .font(.headline)
                            
                            if let suggestion = error.recoverySuggestion {
                                Text("Suggestion: \(suggestion)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    appState.newFile()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            
            CommandGroup(after: .importExport) {
                Button("Open...") {
                    appState.openFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Button("Open Folder...") {
                    appState.openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Save") {
                    appState.saveFile()
                }
                .keyboardShortcut("s", modifiers: [.command])
                
                Button("Save As...") {
                    appState.saveFileAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        .windowResizability(.contentMinSize)
    }
}
