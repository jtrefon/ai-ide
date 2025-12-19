//
//  PTYWrapper.swift
//  osx-ide
//
//  Created by AI Assistant on 19/12/2025.
//

import Foundation
import Darwin

/// Low-level wrapper for pseudo-terminal operations using forkpty
class PTYWrapper {
    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var readHandle: FileHandle?
    private var writeHandle: FileHandle?
    
    /// Resolve the user's default shell path (prefers $SHELL; falls back to pw_shell)
    static func defaultShellPath() -> String {
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], !envShell.isEmpty {
            return envShell
        }
        let pwd = getpwuid(getuid())
        if let pw = pwd, let shellPtr = pw.pointee.pw_shell {
            return String(cString: shellPtr)
        }
        return "/bin/zsh" // final fallback
    }
    
    /// Terminal size structure
    struct TerminalSize {
        var rows: Int32 = 24
        var columns: Int32 = 80
    }
    
    /// Current terminal size
    private var terminalSize = TerminalSize()
    
    /// Callback for when data is received from the PTY
    var onDataReceived: ((Data) -> Void)?
    
    /// Callback for when the shell process terminates
    var onProcessTerminated: (() -> Void)?
    
    deinit {
        cleanup()
    }
    
    /// Initialize PTY and spawn shell
    func initialize(shellPath: String = PTYWrapper.defaultShellPath()) throws {
        print("🔧 PTY: Initializing with shell: \(shellPath)")
        
        // Create pseudo-terminal pair
        let result = Darwin.forkpty(&masterFD, nil, nil, nil)
        print("🔧 PTY: forkpty result: \(result), masterFD: \(masterFD)")
        
        switch result {
        case -1:
            print("❌ PTY: forkpty failed with errno: \(errno)")
            throw PTYError.creationFailed(errno)
            
        case 0:
            // Child process: exec the shell. forkpty already made this process
            // the session leader and connected stdio to the slave pty.
            setenv("TERM", "xterm-256color", 1)
            setenv("COLUMNS", "\(terminalSize.columns)", 1)
            setenv("LINES", "\(terminalSize.rows)", 1)

            let shellPathC = strdup(shellPath)
            let loginArgC = strdup("-l")
            var argv: [UnsafeMutablePointer<CChar>?] = [shellPathC, loginArgC, nil]
            
            // Execute the shell
            execv(shellPathC, &argv)
            
            // If exec fails, print to stderr (which is now the PTY)
            // We use generic C functions to avoid Swift runtime allocation issues in a forked process if possible,
            // though here we are already deep in Swift.
            perror("execv failed")
            _exit(1)
            
        default:
            // Parent process
            childPID = result
            print("✅ PTY: Successfully created PTY, childPID: \(childPID)")
            
            // Set up file handles
            readHandle = FileHandle(fileDescriptor: masterFD)
            writeHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: false)
            
            // Set up asynchronous reading
            setupAsyncReading()
        }
    }
    
    /// Write data to the PTY
    func write(data: Data) throws {
        guard let writeHandle = writeHandle else {
            throw PTYError.notInitialized
        }
        
        writeHandle.write(data)
    }
    
    /// Write string to the PTY
    func write(string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw PTYError.invalidData
        }
        try write(data: data)
    }
    
    /// Resize the terminal
    func resize(size: TerminalSize) throws {
        terminalSize = size
        
        // Set terminal size using TIOCSWINSZ ioctl
        var winsize = winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0)
        winsize.ws_row = UInt16(size.rows)
        winsize.ws_col = UInt16(size.columns)
        winsize.ws_xpixel = 0
        winsize.ws_ypixel = 0
        
        guard ioctl(Int32(masterFD), UInt(TIOCSWINSZ), &winsize) == 0 else {
            throw PTYError.resizeFailed(errno)
        }
        
        // Send SIGWINCH to the shell process
        if childPID > 0 {
            kill(childPID, Int32(SIGWINCH))
        }
    }
    
    /// Get current terminal size
    func getSize() -> TerminalSize {
        return terminalSize
    }
    
    /// Send signal to the shell process
    func sendSignal(_ signal: Int32) {
        guard childPID > 0 else { return }
        kill(childPID, signal)
    }
    
    /// Check if the PTY is initialized
    var isInitialized: Bool {
        return masterFD != -1 && childPID > 0
    }
    
    // MARK: - Private Methods
    
    private func setupAsyncReading() {
        guard let readHandle = readHandle else { return }
        print("🔧 PTY: Setting up readabilityHandler...")
        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self = self else { return }
            if data.isEmpty {
                // EOF: child terminated
                print("📡 PTY: EOF received; process likely terminated")
                self.onProcessTerminated?()
                return
            }
            print("📡 PTY: Received \(data.count) bytes: \(String(data: data, encoding: .utf8) ?? "non-utf8")")
            self.onDataReceived?(data)
        }
        print("✅ PTY: readabilityHandler set")
    }
    
    private func cleanup() {
        readHandle?.readabilityHandler = nil
        // Close file handles
        readHandle?.closeFile()
        writeHandle?.closeFile()
        
        // Close file descriptors
        if masterFD != -1 {
            close(masterFD)
            masterFD = -1
        }
        // Terminate shell process
        if childPID > 0 {
            kill(childPID, SIGTERM)
            childPID = -1
        }
        
        // Removed NotificationCenter observer removal (no longer used)
    }
}

// MARK: - Error Types

enum PTYError: Error, LocalizedError {
    case creationFailed(Int32)
    case notInitialized
    case invalidData
    case resizeFailed(Int32)
    
    var errorDescription: String? {
        switch self {
        case .creationFailed(let errno):
            return "Failed to create PTY: \(String(cString: strerror(errno)))"
        case .notInitialized:
            return "PTY not initialized"
        case .invalidData:
            return "Invalid data for PTY write"
        case .resizeFailed(let errno):
            return "Failed to resize terminal: \(String(cString: strerror(errno)))"
        }
    }
}

// MARK: - C Function Declarations

// Import forkpty and related functions from libutil
@_silgen_name("forkpty")
func forkpty(_ amaster: UnsafeMutablePointer<Int32>?, _ name: UnsafeMutablePointer<Int8>?, _ termp: UnsafeRawPointer?, _ winp: UnsafeRawPointer?) -> Int32

// Terminal size structure
struct winsize {
    var ws_row: UInt16
    var ws_col: UInt16
    var ws_xpixel: UInt16
    var ws_ypixel: UInt16
}

// IOCTL constants
let TIOCSWINSZ = 0x40087468  // Set window size
let SIGWINCH = 28            // Window size change signal
