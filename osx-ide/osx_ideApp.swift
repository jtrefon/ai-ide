//
//  osx_ideApp.swift
//  osx-ide
//
//  Created by Jack Trefon on 25/08/2025.
//

import SwiftUI
import AppKit

@main
struct osx_ideApp: App {
    private let container: DependencyContainer
    @StateObject private var appState: AppState
    @StateObject private var errorManager: ErrorManager
    @AppStorage(AppConstants.Storage.codebaseIndexEnabledKey) private var codebaseIndexEnabled: Bool = true
    @AppStorage(AppConstants.Storage.codebaseIndexAIEnrichmentEnabledKey) private var codebaseIndexAIEnrichmentEnabled: Bool = false
    @State private var didInitializeCorePlugin: Bool = false
    
    init() {
        let container = DependencyContainer()
        self.container = container

        guard let errorMgr = container.errorManager as? ErrorManager else {
            fatalError("DependencyContainer.errorManager must be an ErrorManager")
        }
        let appSt = container.makeAppState()

        if ProcessInfo.processInfo.environment["XCUI_TESTING"] == "1",
           ProcessInfo.processInfo.environment["UI_TEST_SCENARIO"] == "json_highlighting" {
            let json = """
            {
              "key": "value",
              "number": 123,
              "bool": true,
              "nullVal": null,
              "arr": [1, false],
              "obj": {"nested": false}
            }
            """
            appSt.fileEditor.primaryPane.editorContent = json
            appSt.fileEditor.primaryPane.editorLanguage = "json"
        }
        
        self._errorManager = StateObject(wrappedValue: errorMgr)
        self._appState = StateObject(wrappedValue: appSt)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .environmentObject(errorManager)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .task {
                    if ProcessInfo.processInfo.environment["XCUI_TESTING"] == "1" {
                        return
                    }
                    if didInitializeCorePlugin {
                        return
                    }

                    CorePlugin.initialize(registry: appState.uiRegistry, context: appState)
                    didInitializeCorePlugin = true
                }
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
                Button("New Project") {
                    Task { try? await appState.commandRegistry.execute(.projectNew) }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            
            CommandGroup(after: .importExport) {
                Button("Open...") {
                    Task { try? await appState.commandRegistry.execute(.fileOpen) }
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Button("Open Folder...") {
                    Task { try? await appState.commandRegistry.execute(.fileOpenFolder) }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Save") {
                    Task { try? await appState.commandRegistry.execute(.fileSave) }
                }
                .keyboardShortcut("s", modifiers: [.command])
                
                Button("Save As...") {
                    Task { try? await appState.commandRegistry.execute(.fileSaveAs) }
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

                Toggle("Show Hidden Files", isOn: Binding(
                    get: { appState.showHiddenFilesInFileTree },
                    set: { appState.showHiddenFilesInFileTree = $0 }
                ))
                    .keyboardShortcut(".", modifiers: [.command, .shift])
            }

            CommandMenu("Tools") {
                Toggle("Codebase Index Enabled", isOn: $codebaseIndexEnabled)
                    .onChange(of: codebaseIndexEnabled) { _, newValue in
                        appState.setCodebaseIndexEnabled(newValue)
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
                        appState.setAIEnrichmentIndexingEnabled(newValue)
                    }

                Divider()

                Button("Format Document") {
                    Task { try? await appState.commandRegistry.execute(.editorFormat) }
                }
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])

                Button("Reindex Project Now") {
                    appState.reindexProjectNow()
                }
            }

            CommandMenu("Editor") {
                Button("Find") {
                    Task { try? await appState.commandRegistry.execute(.editorFind) }
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Replace") {
                    Task { try? await appState.commandRegistry.execute(.editorReplace) }
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button("AI Inline Assist") {
                    Task { try? await appState.commandRegistry.execute(.editorAIInlineAssist) }
                }
                .keyboardShortcut("i", modifiers: [.command])

                Divider()

                Button("Close Tab") {
                    Task { try? await appState.commandRegistry.execute(.editorTabsCloseActive) }
                }
                .keyboardShortcut("w", modifiers: [.command])

                Button("Close All Tabs") {
                    Task { try? await appState.commandRegistry.execute(.editorTabsCloseAll) }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Next Tab") {
                    Task { try? await appState.commandRegistry.execute(.editorTabsNext) }
                }
                .keyboardShortcut(.tab, modifiers: [.control])

                Button("Previous Tab") {
                    Task { try? await appState.commandRegistry.execute(.editorTabsPrevious) }
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                Button("Split Right") {
                    Task { try? await appState.commandRegistry.execute(.editorSplitRight) }
                }
                .keyboardShortcut("\\", modifiers: [.command])

                Button("Split Down") {
                    Task { try? await appState.commandRegistry.execute(.editorSplitDown) }
                }

                Button("Focus Next Group") {
                    Task { try? await appState.commandRegistry.execute(.editorFocusNextGroup) }
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
            }

            CommandMenu("Search") {
                Button("Find in Workspace") {
                    Task { try? await appState.commandRegistry.execute(.searchFindInWorkspace) }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Command Palette") {
                    Task { try? await appState.commandRegistry.execute(.workbenchCommandPalette) }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            CommandMenu("Go") {
                Button("Quick Open") {
                    Task { try? await appState.commandRegistry.execute(.workbenchQuickOpen) }
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("Go to Symbol") {
                    Task { try? await appState.commandRegistry.execute(.workbenchGoToSymbol) }
                }
                .keyboardShortcut("t", modifiers: [.command])

                Divider()

                Button("Go to Definition") {
                    Task { try? await appState.commandRegistry.execute(.editorGoToDefinition) }
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF12FunctionKey)!)), modifiers: [])

                Button("Find References") {
                    Task { try? await appState.commandRegistry.execute(.editorFindReferences) }
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF12FunctionKey)!)), modifiers: [.shift])

                Button("Rename Symbol") {
                    Task { try? await appState.commandRegistry.execute(.editorRenameSymbol) }
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: [])

                Divider()

                Button("Add Next Occurrence") {
                    Task { try? await appState.commandRegistry.execute(.editorAddNextOccurrence) }
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Add Cursor Above") {
                    Task { try? await appState.commandRegistry.execute(.editorAddCursorAbove) }
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), modifiers: [.command, .option])

                Button("Add Cursor Below") {
                    Task { try? await appState.commandRegistry.execute(.editorAddCursorBelow) }
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), modifiers: [.command, .option])
            }

            CommandMenu("Explorer") {
                Button("Delete", action: {
                    guard let url = appState.selectedFileTreeURL() else { return }
                    Task { try? await appState.commandRegistry.execute(.explorerDeleteSelection, args: ExplorerPathArgs(path: url.path)) }
                })
                .keyboardShortcut(.delete, modifiers: [.command])

                Button("Rename", action: {
                    guard let url = appState.selectedFileTreeURL() else { return }
                    let alert = NSAlert()
                    alert.messageText = "Rename"
                    alert.informativeText = "Enter a new name."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Rename")
                    alert.addButton(withTitle: "Cancel")
                    let textField = NSTextField(string: url.lastPathComponent)
                    textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
                    alert.accessoryView = textField
                    let response = alert.runModal()
                    guard response == .alertFirstButtonReturn else { return }
                    let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !newName.isEmpty else { return }
                    Task {
                        try? await appState.commandRegistry.execute(.explorerRenameSelection, args: ExplorerRenameArgs(path: url.path, newName: newName))
                    }
                })

                Button("Show in Finder", action: {
                    guard let url = appState.selectedFileTreeURL() else { return }
                    Task { try? await appState.commandRegistry.execute(.explorerRevealInFinder, args: ExplorerPathArgs(path: url.path)) }
                })
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
        .windowResizability(.contentMinSize)
        
        Settings {
            SettingsView(ui: appState.ui)
        }
    }
}
