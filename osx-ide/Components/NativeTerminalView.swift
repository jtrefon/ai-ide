//
//  NativeTerminalView.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI
import AppKit

/// Modern terminal view with native zsh shell integration for macOS 26
struct NativeTerminalView: View {
    @StateObject private var embedder: NativeTerminalEmbedder
    @Binding var currentDirectory: URL?
    @ObservedObject var ui: UIStateManager

    init(currentDirectory: Binding<URL?>, ui: UIStateManager, eventBus: EventBusProtocol) {
        self._currentDirectory = currentDirectory
        self.ui = ui
        self._embedder = StateObject(wrappedValue: NativeTerminalEmbedder(eventBus: eventBus))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal header with Liquid Glass UI
            HStack {
                Button(action: {
                    embedder.clearTerminal()
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear Terminal")
                
                Text("Terminal")
                    .font(.system(size: max(10, ui.fontSize - 2), weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(currentDirectory?.lastPathComponent ?? "Terminal")
                    .font(.system(size: max(10, ui.fontSize - 3)))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 30)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Terminal content area using proper NSViewRepresentable
            TerminalContentView(
                embedder: embedder,
                currentDirectory: $currentDirectory,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: ui.fontSize) { _, newValue in
            embedder.updateFont(size: newValue, family: ui.fontFamily)
        }
        .onChange(of: ui.fontFamily) { _, newValue in
            embedder.updateFont(size: ui.fontSize, family: newValue)
        }
        .alert("Terminal Error", isPresented: Binding(
            get: { embedder.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    embedder.errorMessage = nil
                }
            }
        )) {
            Button("OK") {
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

/// NSViewRepresentable that properly embeds the terminal view
struct TerminalContentView: NSViewRepresentable {
    @ObservedObject var embedder: NativeTerminalEmbedder
    @Binding var currentDirectory: URL?
    var fontSize: Double
    var fontFamily: String
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true

        context.coordinator.scheduleEmbed(
            into: containerView,
            directory: currentDirectory,
            embedder: embedder,
            fontSize: fontSize,
            fontFamily: fontFamily
        )
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.scheduleEmbed(
            into: nsView,
            directory: currentDirectory,
            embedder: embedder,
            fontSize: fontSize,
            fontFamily: fontFamily
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var lastEmbeddedPath: String?
        private var lastFontSize: Double?
        private var lastFontFamily: String?

        func scheduleEmbed(into view: NSView, directory: URL?, embedder: NativeTerminalEmbedder, fontSize: Double, fontFamily: String) {
            let path = directory?.standardizedFileURL.path
            guard lastEmbeddedPath != path || lastFontSize != fontSize || lastFontFamily != fontFamily else { return }
            lastEmbeddedPath = path
            lastFontSize = fontSize
            lastFontFamily = fontFamily

            Task { @MainActor in
                await Task.yield()
                embedder.embedTerminal(
                    in: view,
                    directory: directory,
                    fontSize: fontSize,
                    fontFamily: fontFamily
                )
            }
        }
    }
}

#Preview {
    NativeTerminalView(
        currentDirectory: .constant(nil),
        ui: UIStateManager(uiService: UIService(errorManager: ErrorManager(), eventBus: EventBus()), eventBus: EventBus()),
        eventBus: EventBus()
    )
    .frame(width: 600, height: 400)
}
