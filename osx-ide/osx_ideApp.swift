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
    @AppStorage("CodebaseIndexEnabled") private var codebaseIndexEnabled: Bool = true
    @AppStorage("CodebaseIndexAIEnrichmentEnabled") private var codebaseIndexAIEnrichmentEnabled: Bool = false
    @AppStorage("ShowHiddenFilesInFileTree") private var showHiddenFilesInFileTree: Bool = false
    
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

            CommandGroup(after: .sidebar) {
                Toggle("Show File Explorer", isOn: Binding(
                    get: { appState.ui.isSidebarVisible },
                    set: { appState.ui.isSidebarVisible = $0 }
                ))

                Toggle("Show Terminal", isOn: Binding(
                    get: { appState.ui.isTerminalVisible },
                    set: { appState.ui.isTerminalVisible = $0 }
                ))

                Toggle("Show AI Chat", isOn: Binding(
                    get: { appState.ui.isAIChatVisible },
                    set: { appState.ui.isAIChatVisible = $0 }
                ))

                Divider()

                Toggle("Show Hidden Files", isOn: $showHiddenFilesInFileTree)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
            }

            CommandMenu("Tools") {
                Toggle("Codebase Index Enabled", isOn: $codebaseIndexEnabled)
                    .onChange(of: codebaseIndexEnabled) { _, newValue in
                        DependencyContainer.shared.setCodebaseIndexEnabled(newValue)
                    }

                Toggle("AI Enrichment Indexing", isOn: $codebaseIndexAIEnrichmentEnabled)
                    .onChange(of: codebaseIndexAIEnrichmentEnabled) { _, newValue in
                        if newValue {
                            let settings = OpenRouterSettingsStore().load()
                            let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                            if model.isEmpty {
                                errorManager.handle(.aiServiceError("Select an OpenRouter model in Settings before enabling AI enrichment indexing."))
                                codebaseIndexAIEnrichmentEnabled = false
                                return
                            }
                        }
                        DependencyContainer.shared.setAIEnrichmentIndexingEnabled(newValue)
                    }

                Divider()

                Button("Reindex Project Now") {
                    DependencyContainer.shared.reindexProjectNow()
                }
            }
        }
        .windowResizability(.contentMinSize)
        
        Settings {
            SettingsView(appState: appState)
        }
    }
}
