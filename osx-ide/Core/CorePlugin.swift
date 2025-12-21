//
//  CorePlugin.swift
//  osx-ide
//
//  Created by Jack Trefon on 21/12/2025.
//

import SwiftUI

/// The "Default Plugin" that registers the core UI components of the IDE.
/// In the future, these components could be fully separated into their own modules.
@MainActor
final class CorePlugin {
    static func initialize(registry: UIRegistry, appState: AppState) {
        
        // Register File Explorer (Sidebar)
        registry.register(
            point: .sidebarLeft,
            name: "Internal.FileExplorer",
            icon: "folder",
            view: FileExplorerView(appState: appState)
        )
        
        // Register Terminal (Bottom Panel)
        registry.register(
            point: .panelBottom,
            name: "Internal.Terminal",
            icon: "terminal",
            view: NativeTerminalView(currentDirectory: appState.currentDirectory)
        )
        
        // Register AI Chat (Right Panel)
        registry.register(
            point: .panelRight,
            name: "Internal.AIChat",
            icon: "sparkles",
            view: AIChatPanel(
                selectionContext: appState.selectionContext, // Use shared context
                conversationManager: appState.conversationManager
            )
        )
        
        print("[CorePlugin] Initialized core UI components")
    }
}
