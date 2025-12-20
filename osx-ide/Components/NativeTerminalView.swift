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
        
        // Embed terminal immediately when view is created
        embedder.embedTerminal(in: containerView, directory: currentDirectory)
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update if directory changes
        if let currentDir = currentDirectory, currentDir != embedder.currentDirectory {
            embedder.removeEmbedding()
            embedder.embedTerminal(in: nsView, directory: currentDir)
        }
    }
}

#Preview {
    NativeTerminalView()
        .frame(width: 600, height: 400)
}
