//
//  PanelCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import AppKit

/// Manages terminal and bottom panel configuration and rendering
@MainActor
struct PanelCoordinator {
    
    // MARK: - Properties
    
    let registry: UIRegistry
    let ui: UIStateManager

    // MARK: - Initialization
    
    // MARK: - Public Methods
    
    /// Creates the terminal panel view
    @ViewBuilder
    func makeTerminalPanel() -> some View {
        let bottomViews = registry.views(for: .panelBottom)

        if bottomViews.count == 1, let pluginView = bottomViews.first {
            pluginView.makeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .frame(minHeight: 100)
        } else if bottomViews.count > 1 {
            let selectedName = ui.bottomPanelSelectedName
            let selectedView = bottomViews.first(where: { $0.name == selectedName }) ?? bottomViews[0]

            selectedView.makeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .frame(minHeight: 100)
        } else {
            EmptyView()
        }
    }
    
    /// Creates the sidebar view
    @ViewBuilder
    func makeSidebar() -> some View {
        let sidebarViews = registry.views(for: .sidebarLeft)
        
        if let sidebarView = sidebarViews.first {
            sidebarView.makeView()
                .frame(minWidth: 200, maxWidth: 300)
                .background(Color(NSColor.windowBackgroundColor))
        } else {
            // Empty sidebar
            VStack {
                Text("Sidebar")
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 200, maxWidth: 300)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    /// Creates the right panel view
    @ViewBuilder
    func makeRightPanel() -> some View {
        let rightViews = registry.views(for: .panelRight)

        if ui.isAIChatVisible, let pluginView = rightViews.first {
            pluginView.makeView()
                .frame(minWidth: 240, idealWidth: 340, maxWidth: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        } else {
            EmptyView()
        }
    }
}
