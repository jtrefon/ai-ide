//
//  osx_ideApp.swift
//  osx-ide
//
//  Created by Jack Trefon on 25/08/2025.
//

import SwiftUI

@main
struct osx_ideApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
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
