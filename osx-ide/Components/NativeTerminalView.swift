//
//  NativeTerminalView.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI
import AppKit
import Combine

/// Modern terminal view with native zsh shell integration for macOS 26
struct NativeTerminalView: View {
    @StateObject private var embedder: NativeTerminalEmbedder
    @Binding var currentDirectory: URL?
    @ObservedObject var ui: UIStateManager
    private let eventBus: EventBusProtocol
    @State private var clearSubscription: AnyCancellable?

    init(currentDirectory: Binding<URL?>, ui: UIStateManager, eventBus: EventBusProtocol) {
        self._currentDirectory = currentDirectory
        self.ui = ui
        self.eventBus = eventBus
        self._embedder = StateObject(wrappedValue: NativeTerminalEmbedder(eventBus: eventBus))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal content area using proper NSViewRepresentable
            TerminalContentView(
                embedder: embedder,
                currentDirectory: $currentDirectory,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            clearSubscription = eventBus.subscribe(to: TerminalClearRequestedEvent.self) { [weak embedder] _ in
                embedder?.clearTerminal()
            }
        }
        .onDisappear {
            clearSubscription = nil
        }
        .onChange(of: ui.fontSize) { _, newValue in
            embedder.updateFont(size: newValue, family: ui.fontFamily)
        }
        .onChange(of: ui.fontFamily) { _, newValue in
            embedder.updateFont(size: ui.fontSize, family: newValue)
        }
        .alert(NSLocalizedString("terminal.error.title", comment: ""), isPresented: Binding(
            get: { embedder.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    embedder.errorMessage = nil
                }
            }
        )) {
            Button(NSLocalizedString("common.ok", comment: "")) {
                embedder.errorMessage = nil
            }
        } message: {
            if let error = embedder.errorMessage {
                Text(error)
            }
        }
        .onDisappear {
            embedder.removeEmbedding()
        }
    }
}
