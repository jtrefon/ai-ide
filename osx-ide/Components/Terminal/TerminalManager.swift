//
//  TerminalManager.swift
//  osx-ide
//
//  Created by AI Assistant on 19/12/2025.
//

import Foundation
import AppKit

/// Manages the native terminal session with PTY support
class TerminalManager: ObservableObject {
    @Published var isInitialized = false
    @Published var errorMessage: String?
    
    private var ptyWrapper: PTYWrapper?
    private var emulator: TerminalEmulator?
    private var terminalSize = PTYWrapper.TerminalSize(rows: 24, columns: 80)
    
    /// Callback for screen content updates
    var onScreenUpdate: (([[TerminalCharacter]], (row: Int, column: Int)) -> Void)?
    
    /// Callback for terminal termination
    var onTerminalTerminated: (() -> Void)?
    
    /// Error handler closure
    private let errorHandler: ((String) -> Void)?
    
    init(errorHandler: ((String) -> Void)? = nil) {
        self.errorHandler = errorHandler
    }
    
    deinit {
        cleanup()
    }
    
    /// Initialize the terminal session
    func initialize(rows: Int = 24, columns: Int = 80, shellPath: String? = nil) {
        terminalSize = PTYWrapper.TerminalSize(rows: Int32(rows), columns: Int32(columns))
        
        // Verify shell path exists
        let effectiveShellPath = shellPath ?? PTYWrapper.defaultShellPath()
        if !FileManager.default.fileExists(atPath: effectiveShellPath) {
             handleError("Shell not found at path: \(effectiveShellPath)")
             return
        }
        
        do {
            // Create emulator first so we don't lose early output from the shell (prompt, init sequences)
            emulator = TerminalEmulator(rows: rows, columns: columns)
            
            // Set up emulator callbacks
            emulator?.onScreenUpdate = { [weak self] in
                self?.notifyScreenUpdate()
            }
            
            emulator?.onCursorUpdate = { [weak self] in
                self?.notifyScreenUpdate()
            }

            // Create PTY wrapper
            ptyWrapper = PTYWrapper()
            
            // Set up callbacks
            ptyWrapper?.onDataReceived = { [weak self] data in
                self?.handlePTYData(data)
            }
            
            ptyWrapper?.onProcessTerminated = { [weak self] in
                self?.handleProcessTermination()
            }
            
            // Initialize PTY
            try ptyWrapper?.initialize(shellPath: effectiveShellPath)
            
            // Set terminal size
            try ptyWrapper?.resize(size: terminalSize)
            
            // Nudge the shell to render a prompt in case it's waiting
            // We use a slightly longer delay to ensure PTY is fully ready
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.write(string: "\r")
            }
            
            isInitialized = true
            errorMessage = nil
            
        } catch {
            handleError("Failed to initialize terminal: \(error.localizedDescription)")
        }
    }
    
    /// Write data to the terminal
    func write(data: Data) {
        guard let ptyWrapper = ptyWrapper else {
            handleError("Terminal not initialized")
            return
        }
        
        do {
            try ptyWrapper.write(data: data)
        } catch {
            handleError("Failed to write to terminal: \(error.localizedDescription)")
        }
    }
    
    /// Write string to the terminal
    func write(string: String) {
        guard let data = string.data(using: .utf8) else {
            handleError("Invalid string data")
            return
        }
        write(data: data)
    }
    
    /// Resize the terminal
    func resize(rows: Int, columns: Int) {
        terminalSize = PTYWrapper.TerminalSize(rows: Int32(rows), columns: Int32(columns))
        
        emulator?.resize(rows: rows, columns: columns)
        
        do {
            try ptyWrapper?.resize(size: terminalSize)
        } catch {
            handleError("Failed to resize terminal: \(error.localizedDescription)")
        }
    }
    
    /// Send signal to the shell process
    func sendSignal(_ signal: Int32) {
        ptyWrapper?.sendSignal(signal)
    }
    
    /// Clear the terminal screen
    func clear() {
        emulator?.resize(rows: Int(terminalSize.rows), columns: Int(terminalSize.columns))
    }
    
    /// Get current terminal size
    func getSize() -> PTYWrapper.TerminalSize {
        return terminalSize
    }
    
    // MARK: - Private Methods
    
    private func handlePTYData(_ data: Data) {
        // Log received data for debugging (can be removed later)
        // print("TerminalManager: Received \(data.count) bytes")
        emulator?.processData(data)
    }
    
    private func handleProcessTermination() {
        isInitialized = false
        onTerminalTerminated?()
        errorHandler?("Terminal session terminated")
    }
    
    private func notifyScreenUpdate() {
        guard let emulator = emulator else { return }
        
        let screenContent = emulator.getScreenContent()
        let cursorPosition = emulator.getCursorPosition()
        
        DispatchQueue.main.async {
            self.onScreenUpdate?(screenContent, cursorPosition)
        }
    }
    
    private func handleError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.errorHandler?(message)
        }
    }
    
    private func cleanup() {
        ptyWrapper = nil
        emulator = nil
        isInitialized = false
    }
}

// MARK: - Keyboard Input Handling

extension TerminalManager {
    
    /// Handle key press events
    func handleKeyPress(_ event: NSEvent) -> Bool {
        guard isInitialized else { return false }
        
        let modifiers = event.modifierFlags
        let characters = event.characters
        let charactersIgnoringModifiers = event.charactersIgnoringModifiers
        
        // Handle special key combinations
        if modifiers.contains(.control) {
            return handleControlKey(charactersIgnoringModifiers)
        }
        
        // Handle function keys and special keys
        if let characters = characters {
            return handleSpecialKeys(characters, modifiers: modifiers)
        }
        
        return false
    }
    
    private func handleControlKey(_ characters: String?) -> Bool {
        guard let characters = characters else { return false }
        
        switch characters {
        case "c": // Ctrl+C
            sendSignal(SIGINT)
            return true
        case "d": // Ctrl+D
            write(string: "\u{4}") // End of transmission
            return true
        case "z": // Ctrl+Z
            sendSignal(SIGTSTP)
            return true
        case "l": // Ctrl+L
            write(string: "\u{0C}") // Form feed (clear screen)
            return true
        default:
            return false
        }
    }
    
    private func handleSpecialKeys(_ characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch characters {
        case "\u{7F}": // Delete/Backspace
            write(string: "\u{7F}")
            return true
        case "\r": // Enter/Return
            write(string: "\r")
            return true
        case "\t": // Tab
            write(string: "\t")
            return true
        case "\u{19}": // Tab with shift (backtab)
            write(string: "\u{1B}[Z")
            return true
        case "\u{1B}": // Escape
            write(string: "\u{1B}")
            return true
        default:
            // Regular printable characters
            if characters.unicodeScalars.allSatisfy({ $0.isPrintableASCII }) {
                write(string: characters)
                return true
            }
            return false
        }
    }
    
    /// Handle arrow keys and other special keys using keyCode
    func handleSpecialKeyCode(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard isInitialized else { return false }
        
        let control = modifiers.contains(.control)
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)
        
        switch keyCode {
        case 123: // Left arrow
            if control && option {
                write(string: "\u{1B}[5D") // Ctrl+Option+Left
            } else if control {
                write(string: "\u{1B}[1;5D") // Ctrl+Left
            } else if option {
                write(string: "\u{1B}b") // Option+Left (word back)
            } else {
                write(string: "\u{1B}[D") // Left
            }
            return true
            
        case 124: // Right arrow
            if control && option {
                write(string: "\u{1B}[5C") // Ctrl+Option+Right
            } else if control {
                write(string: "\u{1B}[1;5C") // Ctrl+Right
            } else if option {
                write(string: "\u{1B}f") // Option+Right (word forward)
            } else {
                write(string: "\u{1B}[C") // Right
            }
            return true
            
        case 125: // Down arrow
            if shift {
                write(string: "\u{1B}[1;2B") // Shift+Down
            } else if control {
                write(string: "\u{1B}[1;5B") // Ctrl+Down
            } else {
                write(string: "\u{1B}[B") // Down
            }
            return true
            
        case 126: // Up arrow
            if shift {
                write(string: "\u{1B}[1;2A") // Shift+Up
            } else if control {
                write(string: "\u{1B}[1;5A") // Ctrl+Up
            } else {
                write(string: "\u{1B}[A") // Up
            }
            return true
            
        case 116: // Page Up
            if shift {
                write(string: "\u{1B}[5;2~") // Shift+PageUp
            } else if control {
                write(string: "\u{1B}[5;5~") // Ctrl+PageUp
            } else {
                write(string: "\u{1B}[5~") // PageUp
            }
            return true
            
        case 121: // Page Down
            if shift {
                write(string: "\u{1B}[6;2~") // Shift+PageDown
            } else if control {
                write(string: "\u{1B}[6;5~") // Ctrl+PageDown
            } else {
                write(string: "\u{1B}[6~") // PageDown
            }
            return true
            
        case 115: // Home
            if shift {
                write(string: "\u{1B}[1;2H") // Shift+Home
            } else if control {
                write(string: "\u{1B}[1;5H") // Ctrl+Home
            } else {
                write(string: "\u{1B}[H") // Home
            }
            return true
            
        case 119: // End
            if shift {
                write(string: "\u{1B}[1;2F") // Shift+End
            } else if control {
                write(string: "\u{1B}[1;5F") // Ctrl+End
            } else {
                write(string: "\u{1B}[F") // End
            }
            return true
            
        case 117: // Delete
            write(string: "\u{1B}[3~") // Delete
            return true
            
        case 53: // Escape
            write(string: "\u{1B}") // Escape
            return true
            
        default:
            return false
        }
    }
}

// MARK: - Unicode Extension

private extension UnicodeScalar {
    var isPrintableASCII: Bool {
        return value >= 32 && value <= 126
    }
}
