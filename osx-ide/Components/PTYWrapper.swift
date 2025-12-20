//
//  PTYWrapper.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation

/// Wrapper for shell process with pipes (simplified approach for macOS permissions)
@MainActor
class PTYWrapper {
    private var process: Process?
    private var readHandle: FileHandle?
    private var writeHandle: FileHandle?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?
    private var readTask: Task<Void, Never>?
    
    init() {}
    
    deinit {
        // Cleanup handled by terminateProcess() called from main actor
        readTask?.cancel()
        readTask = nil
        process?.terminate()
        process = nil
        readHandle?.closeFile()
        writeHandle?.closeFile()
        outputPipe = nil
        inputPipe = nil
    }
    
    /// Start a shell process with pipes
    func startProcess(shell: String, args: [String], cwd: String?) -> Bool {
        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = args
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        
        // Set up pipes for I/O
        process.standardOutput = outputPipe
        process.standardInput = inputPipe
        process.standardError = outputPipe
        
        // Set up environment for proper shell behavior
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLUMNS"] = "80"
        environment["LINES"] = "24"
        environment["FORCE_INTERACTIVE"] = "1"
        process.environment = environment
        
        // Store references
        self.process = process
        self.outputPipe = outputPipe
        self.inputPipe = inputPipe
        
        // Set up reading from output
        readHandle = outputPipe.fileHandleForReading
        writeHandle = inputPipe.fileHandleForWriting
        
        do {
            try process.run()
            
            // Start monitoring output
            startOutputMonitoring()
            
            return true
        } catch {
            print("Failed to start shell process: \(error)")
            return false
        }
    }
    
    /// Start monitoring output
    private func startOutputMonitoring() {
        readTask = Task { @MainActor in
            while await readOutput() != nil {
                // Continue reading while data is available
            }
        }
    }
    
    /// Read output from process
    func readOutput() async -> Data? {
        guard let readHandle = readHandle else { return nil }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let data = readHandle.availableData
                if !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    // Check if process is still running
                    let isRunning = self?.process?.isRunning ?? false
                    if !isRunning {
                        continuation.resume(returning: nil)
                    } else {
                        // Wait a bit and try again
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.01) {
                            let retryData = readHandle.availableData
                            continuation.resume(returning: retryData.isEmpty ? nil : retryData)
                        }
                    }
                }
            }
        }
    }
    
    /// Write input to process
    func writeInput(_ data: Data) {
        writeHandle?.write(data)
    }
    
    /// Write string to process
    func writeString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        writeInput(data)
    }
    
    /// Get window size (placeholder for compatibility)
    func getWindowSize() -> winsize {
        var ws = winsize()
        ws.ws_row = 24
        ws.ws_col = 80
        return ws
    }
    
    /// Set window size (placeholder for compatibility)
    func setWindowSize(_ size: winsize) {
        // Not applicable for pipe-based approach
    }
    
    /// Terminate the process
    func terminateProcess() {
        readTask?.cancel()
        readTask = nil
        
        process?.terminate()
        process = nil
        readHandle?.closeFile()
        writeHandle?.closeFile()
        outputPipe = nil
        inputPipe = nil
    }
}
