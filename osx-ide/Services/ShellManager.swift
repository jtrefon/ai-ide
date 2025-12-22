//
//  ShellManager.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation
import AppKit
import Darwin

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
    private var ptyMasterFD: Int32?
    private var ptySlaveFD: Int32?
    
    private let queue = DispatchQueue(label: "com.osx-ide.shell-manager", qos: .userInitiated)
    private let cleanupLock = NSLock()
    nonisolated(unsafe) private var _isCleaningUp = false
    nonisolated private var isCleaningUp: Bool {
        get { cleanupLock.withLock { _isCleaningUp } }
        set { cleanupLock.withLock { _isCleaningUp = newValue } }
    }
    
    /// Start the shell process in the specified directory
    func start(in directory: URL? = nil) {
        start(in: directory, arguments: ["-i"], environmentOverrides: [:])
    }

    func start(in directory: URL? = nil, arguments: [String], environmentOverrides: [String: String]) {
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

        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            notifyError("Failed to create PTY")
            return
        }

        // Configure a reasonable initial window size so shells that depend on it behave.
        var winSize = winsize(
            ws_row: UInt16(AppConstants.Terminal.defaultRows),
            ws_col: UInt16(AppConstants.Terminal.defaultColumns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(master, TIOCSWINSZ, &winSize)

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: false)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = arguments
        process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = environmentOverrides["TERM"] ?? "xterm-256color"
        environment["COLUMNS"] = environmentOverrides["COLUMNS"] ?? "\(AppConstants.Terminal.defaultColumns)"
        environment["LINES"] = environmentOverrides["LINES"] ?? "\(AppConstants.Terminal.defaultRows)"
        environment["PROMPT"] = environmentOverrides["PROMPT"] ?? "$ "
        environment["PROMPT_EOL_MARK"] = environmentOverrides["PROMPT_EOL_MARK"] ?? ""
        environment["ZSH_THEME"] = environmentOverrides["ZSH_THEME"] ?? ""
        environment["DISABLE_AUTO_TITLE"] = environmentOverrides["DISABLE_AUTO_TITLE"] ?? "true"
        for (k, v) in environmentOverrides {
            environment[k] = v
        }
        process.environment = environment

        self.shellProcess = process
        self.ptyMasterFD = master
        self.ptySlaveFD = slave
        self.readHandle = masterHandle
        self.writeHandle = masterHandle

        setupOutputMonitoring()

        do {
            try process.run()

            // Parent no longer needs to hold the slave side open once the child is running.
            try? slaveHandle.close()
            self.ptySlaveFD = nil

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
            guard let self = self, !self.isCleaningUp else { return }
            
            let data = handle.availableData
            guard !data.isEmpty else {
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isCleaningUp else { return }
                    if self.shellProcess?.isRunning == false {
                        self.delegate?.shellManagerDidTerminate(self)
                    }
                }
                return
            }
            
            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isCleaningUp else { return }
                    self.delegate?.shellManager(self, didProduceOutput: output)
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
        ptyMasterFD = nil
        ptySlaveFD = nil
    }
    
    private func notifyError(_ message: String) {
        Task { @MainActor in
            self.delegate?.shellManager(self, didFailWithError: message)
        }
    }
}
