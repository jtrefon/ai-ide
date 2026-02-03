//
//  LayoutCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import AppKit

/// Manages the main application layout and panel resizing
@MainActor
struct LayoutCoordinator {

    // MARK: - Properties

    let ui: UIStateManager

    // MARK: - Initialization

    // MARK: - Public Methods

    /// Creates the main application layout
    func makeMainLayout<Sidebar: View, Editor: View, RightPanel: View, Terminal: View>(
        sidebar: Sidebar,
        editor: Editor,
        rightPanel: RightPanel,
        terminal: Terminal
    ) -> some View {
        LayoutView(
            ui: ui,
            sidebar: AnyView(sidebar),
            editor: AnyView(editor),
            rightPanel: AnyView(rightPanel),
            terminal: AnyView(terminal)
        )
    }
}
