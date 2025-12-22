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
    @StateObject private var embedder = NativeTerminalEmbedder()
    
    let currentDirectory: URL?
    
    init(currentDirectory: URL? = nil) {
        self.currentDirectory = currentDirectory
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(currentDirectory?.lastPathComponent ?? "Terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 30)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Terminal content area using proper NSViewRepresentable
            TerminalContentView(embedder: embedder, currentDirectory: currentDirectory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let currentDirectory: URL?
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true

        context.coordinator.scheduleEmbed(into: containerView, directory: currentDirectory, embedder: embedder)
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.scheduleEmbed(into: nsView, directory: currentDirectory, embedder: embedder)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var lastEmbeddedPath: String?

        func scheduleEmbed(into view: NSView, directory: URL?, embedder: NativeTerminalEmbedder) {
            let path = directory?.standardizedFileURL.path
            guard lastEmbeddedPath != path else { return }
            lastEmbeddedPath = path

            Task { @MainActor in
                await Task.yield()
                embedder.embedTerminal(in: view, directory: directory)
            }
        }
    }
}

#Preview {
    NativeTerminalView()
        .frame(width: 600, height: 400)
}
