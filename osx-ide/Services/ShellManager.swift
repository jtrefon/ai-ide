//
//  ShellManager.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation
import AppKit

/// Protocol for monitoring shell output
protocol ShellManagerDelegate: AnyObject {
    @MainActor func shellManager(_ manager: ShellManager, didProduceOutput output: String)
    @MainActor func shellManager(_ manager: ShellManager, didFailWithError error: String)
    @MainActor func shellManagerDidTerminate(_ manager: ShellManager)
}

/// Decoupled shell process manager handling low-level IO and process lifecycle
@MainActor
class ShellManager: NSObject {
    weak var delegate: ShellManagerDelegate?
    
    private var shellProcess: Process?
    private var readHandle: FileHandle?
    private var writeHandle: FileHandle?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?
    
    private let queue = DispatchQueue(label: "com.osx-ide.shell-manager", qos: .userInitiated)
    private var isCleaningUp = false
    
    /// Start the shell process in the specified directory
    func start(in directory: URL? = nil) {
        cleanup()
        isCleaningUp = false
        
        let shellPath: String
        if FileManager.default.fileExists(atPath: "/bin/zsh") {
            shellPath = "/bin/zsh"
        } else if FileManager.default.fileExists(atPath: "/bin/bash") {
            shellPath = "/bin/bash"
        } else {
            notifyError("No suitable shell found (zsh or bash required)")
            return
        }
        
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            notifyError("Shell at \(shellPath) is not executable")
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-i"]
        process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
        
        process.standardOutput = outputPipe
        process.standardInput = inputPipe
        process.standardError = outputPipe
        
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm"
        environment["COLUMNS"] = "\(AppConstants.Terminal.defaultColumns)"
        environment["LINES"] = "\(AppConstants.Terminal.defaultRows)"
        environment["PROMPT"] = "$ "
        environment["PROMPT_EOL_MARK"] = ""
        environment["ZSH_THEME"] = ""
        environment["DISABLE_AUTO_TITLE"] = "true"
        process.environment = environment
        
        self.shellProcess = process
        self.outputPipe = outputPipe
        self.inputPipe = inputPipe
        self.readHandle = outputPipe.fileHandleForReading
        self.writeHandle = inputPipe.fileHandleForWriting
        
        setupOutputMonitoring()
        
        do {
            try process.run()
            
            // Re-verify after a short delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                if let isRunning = self.shellProcess?.isRunning, !isRunning {
                    self.notifyError("Process failed to start. Please check full disk access permissions.")
                    self.cleanup()
                }
            }
        } catch {
            notifyError("Failed to start shell: \(error.localizedDescription)")
            cleanup()
        }
    }
    
    /// Send input string to the shell
    func sendInput(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        sendInput(data)
    }
    
    /// Send raw input data to the shell
    func sendInput(_ data: Data) {
        guard !isCleaningUp, let writeHandle = writeHandle else { return }
        queue.async {
            do {
                try writeHandle.write(contentsOf: data)
            } catch {
                print("Shell input error: \(error)")
            }
        }
    }
    
    /// Interrupt the current shell process
    func interrupt() {
        if let process = shellProcess, process.isRunning {
            process.interrupt()
        }
        sendInput("\u{03}") // Ctrl+C
    }
    
    /// Terminate the shell process
    func terminate() {
        cleanup()
    }
    
    // MARK: - Private Methods
    
    private func setupOutputMonitoring() {
        guard let readHandle = readHandle else { return }
        
        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                Task { @MainActor in
                    if self?.shellProcess?.isRunning == false {
                        if let self = self {
                            self.delegate?.shellManagerDidTerminate(self)
                        }
                    }
                }
                return
            }
            
            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    if let self = self {
                        self.delegate?.shellManager(self, didProduceOutput: output)
                    }
                }
            }
        }
    }
    
    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        let handleToClose = readHandle
        let writeToClose = writeHandle
        readHandle?.readabilityHandler = nil
        
        if let process = shellProcess, process.isRunning {
            process.terminate()
            queue.asyncAfter(deadline: .now() + 0.1) {
                if process.isRunning { process.interrupt() }
                try? handleToClose?.close()
                try? writeToClose?.close()
            }
        } else {
            try? handleToClose?.close()
            try? writeToClose?.close()
        }
        
        shellProcess = nil
        readHandle = nil
        writeHandle = nil
        outputPipe = nil
        inputPipe = nil
    }
    
    private func notifyError(_ message: String) {
        Task { @MainActor in
            self.delegate?.shellManager(self, didFailWithError: message)
        }
    }
}
