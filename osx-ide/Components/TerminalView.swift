//
//  TerminalView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//  Updated for native PTY terminal implementation on 19/12/2025.
//

import SwiftUI

class TerminalAppState: ObservableObject {
    @Published var lastError: String? = nil
}

struct TerminalView: View {
    @StateObject private var appState = TerminalAppState()
    @StateObject private var terminalManager: TerminalManager
    @State private var screenContent: [[TerminalCharacter]] = []
    @State private var cursorPosition: (row: Int, column: Int) = (0, 0)
    @State private var hasFocus = false
    @State private var debugStatus: String = "Initializing..."
    
    init() {
        // Pass an error handler closure to TerminalManager to report errors to appState
        let appState = TerminalAppState()
        _appState = StateObject(wrappedValue: appState)
        _terminalManager = StateObject(wrappedValue: TerminalManager(errorHandler: { errorMessage in
            // Update AppState's lastError to show error in main error banner
            DispatchQueue.main.async {
                appState.lastError = errorMessage
            }
        }))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal header
            HStack {
                Text("Terminal")
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                Button(action: {
                    do {
                        try terminalManager.clear()
                    } catch {
                        // Surface error to AppState's lastError for main error banner
                        appState.lastError = "Failed to clear terminal: \(error.localizedDescription)"
                    }
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.horizontal)
            }
            .frame(height: 30)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Terminal content with integrated input
            ZStack {
                TerminalRenderer(
                    screenContent: screenContent,
                    cursorPosition: cursorPosition,
                    onKeyPress: { event in
                        terminalManager.handleKeyPress(event) || terminalManager.handleSpecialKeyCode(event.keyCode, modifiers: event.modifierFlags)
                    }
                )
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Debug Status Overlay (Top Right)
                Text(debugStatus)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
                
                // Error Overlay (Center)
                if let error = appState.lastError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                        Text("Terminal Error")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button("Dismiss") {
                            appState.lastError = nil
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(40)
                    .frame(maxWidth: 400)
                }
                
                // Focus indicator overlay
                if hasFocus {
                    Rectangle()
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .onTapGesture {
                // Terminal renderer will handle first responder automatically
                hasFocus = true
            }
        }
        .frame(minHeight: 200)
        .onAppear {
            setupTerminal()
        }
        .onDisappear {
            cleanupTerminal()
        }
        .onChange(of: terminalManager.errorMessage) { errorMessage in
            if let error = errorMessage {
                appState.lastError = error
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
            handleTerminalResize()
        }
    }
    
    private func setupTerminal() {
        debugStatus = "Setting up callbacks..."
        // Set up terminal manager callbacks
        terminalManager.onScreenUpdate = { [self] content, cursor in
            print("View: onScreenUpdate received. Rows: \(content.count), Cursor: \(cursor)")
            if !content.isEmpty {
                let firstChars = content[0].prefix(10).map { String($0.char) }.joined()
                print("View: First row preview: '\(firstChars)'")
            }
            screenContent = content
            cursorPosition = cursor
            debugStatus = "Screen updated: \(content.count) lines"
        }
        
        terminalManager.onTerminalTerminated = {
            appState.lastError = "Terminal session terminated"
            debugStatus = "Session terminated"
        }
        
        debugStatus = "Initializing terminal..."
        // Initialize terminal with default size
        terminalManager.initialize(rows: 24, columns: 80)
        
        debugStatus = "Terminal initialized: \(terminalManager.isInitialized ? "YES" : "NO")"
        if let error = terminalManager.errorMessage {
            debugStatus = "Error: \(error)"
        }
        
        // Make first responder after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            makeFirstResponder()
        }
    }
    
    private func cleanupTerminal() {
        // Terminal manager will clean up automatically in deinit
    }
    
    private func makeFirstResponder() {
        // The terminal renderer view should handle first responder status directly
        hasFocus = true
    }
    
    
    private func handleTerminalResize() {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }
        
        // Calculate new terminal size based on window content view
        // Assuming terminal takes most of the space below header (30px)
        let availableHeight = contentView.frame.height - 30 // Subtract header height
        let availableWidth = contentView.frame.width
        
        // Calculate character dimensions (approximate)
        let charWidth: CGFloat = 8.0  // Monospace character width
        let charHeight: CGFloat = 16.0 // Monospace character height
        
        let columns = max(40, Int(availableWidth / charWidth))
        let rows = max(10, Int(availableHeight / charHeight))
        
        print("View: Resize calculated. Available: \(availableWidth)x\(availableHeight). Cols/Rows: \(columns)x\(rows)")
        
        // Resize terminal if size changed
        let currentSize = terminalManager.getSize()
        if currentSize.rows != Int32(rows) || currentSize.columns != Int32(columns) {
            terminalManager.resize(rows: rows, columns: columns)
        }
    }
}

#Preview {
    TerminalView()
        .frame(height: 300)
}
