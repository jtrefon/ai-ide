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
        let errorMgr = container.errorManager as! ErrorManager
        let appSt = container.makeAppState()
        
        self._errorManager = StateObject(wrappedValue: errorMgr)
        self._appState = StateObject(wrappedValue: appSt)
        
        // Bootstrap Plugin UI
        CorePlugin.initialize(registry: UIRegistry.shared, appState: appSt)
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
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    Task { try? await CommandRegistry.shared.execute(.fileNew) }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            
            CommandGroup(after: .importExport) {
                Button("Open...") {
                    Task { try? await CommandRegistry.shared.execute(.fileOpen) }
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Button("Open Folder...") {
                    Task { try? await CommandRegistry.shared.execute(.fileOpenFolder) }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Save") {
                    Task { try? await CommandRegistry.shared.execute(.fileSave) }
                }
                .keyboardShortcut("s", modifiers: [.command])
                
                Button("Save As...") {
                    Task { try? await CommandRegistry.shared.execute(.fileSaveAs) }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        .windowResizability(.contentMinSize)
        
        Settings {
            SettingsView(appState: appState)
        }
    }
}
