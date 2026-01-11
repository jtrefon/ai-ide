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
        start(in: directory, arguments: ["-l", "-i"], environmentOverrides: [:])
    }

    func start(in directory: URL? = nil, arguments: [String], environmentOverrides: [String: String]) {
        cleanup()
        isCleaningUp = false

        guard let shellPath = Self.resolveShellPath(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        ) else {
            notifyError("No suitable shell found (zsh or bash required)")
            return
        }

        if !FileManager.default.isExecutableFile(atPath: shellPath) {
            notifyError("Shell at \(shellPath) is not executable")
            return
        }

        guard let pty = createPTY() else {
            notifyError("Failed to create PTY")
            return
        }

        let process = configureProcess(
            shellPath: shellPath,
            arguments: arguments,
            directory: directory,
            slaveHandle: pty.slaveHandle,
            environmentOverrides: environmentOverrides
        )

        registerRunningProcess(process, pty: pty)
        setupOutputMonitoring()

        do {
            try process.run()
            finalizeStartAfterRun(slaveHandle: pty.slaveHandle)
            schedulePostLaunchVerification()
        } catch {
            notifyError("Failed to start shell: \(error.localizedDescription)")
            cleanup()
        }
    }

    nonisolated static func resolveShellPath(
        fileExists: (String) -> Bool,
        isExecutable: (String) -> Bool
    ) -> String? {
        let candidates = ["/bin/zsh", "/bin/bash"]
        for path in candidates where fileExists(path) {
            if isExecutable(path) {
                return path
            }
        }
        return nil
    }

    private struct PTYHandles {
        let masterFD: Int32
        let slaveFD: Int32
        let masterHandle: FileHandle
        let slaveHandle: FileHandle
    }

    private func createPTY() -> PTYHandles? {
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            return nil
        }

        var winSize = winsize(
            ws_row: UInt16(AppConstants.Terminal.defaultRows),
            ws_col: UInt16(AppConstants.Terminal.defaultColumns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(master, TIOCSWINSZ, &winSize)

        return PTYHandles(
            masterFD: master,
            slaveFD: slave,
            masterHandle: FileHandle(fileDescriptor: master, closeOnDealloc: false),
            slaveHandle: FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        )
    }

    private func configureProcess(
        shellPath: String,
        arguments: [String],
        directory: URL?,
        slaveHandle: FileHandle,
        environmentOverrides: [String: String]
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = arguments
        process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        process.environment = Self.buildEnvironment(environmentOverrides: environmentOverrides)
        return process
    }

    private func registerRunningProcess(_ process: Process, pty: PTYHandles) {
        shellProcess = process
        ptyMasterFD = pty.masterFD
        ptySlaveFD = pty.slaveFD
        readHandle = pty.masterHandle
        writeHandle = pty.masterHandle
    }

    nonisolated static func buildEnvironment(environmentOverrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = environmentOverrides["TERM"] ?? "xterm-256color"
        environment["COLUMNS"] = environmentOverrides["COLUMNS"] ?? "\(AppConstants.Terminal.defaultColumns)"
        environment["LINES"] = environmentOverrides["LINES"] ?? "\(AppConstants.Terminal.defaultRows)"

        if environment["HOME"]?.isEmpty ?? true {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }

        if environmentOverrides["PROMPT_EOL_MARK"] == nil {
            environment["PROMPT_EOL_MARK"] = ""
        }
        for (k, v) in environmentOverrides {
            environment[k] = v
        }
        return environment
    }

    private func finalizeStartAfterRun(slaveHandle: FileHandle) {
        try? slaveHandle.close()
        ptySlaveFD = nil
    }

    private func schedulePostLaunchVerification() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let isRunning = self.shellProcess?.isRunning, !isRunning {
                self.notifyError("Process failed to start. Please check full disk access permissions.")
                self.cleanup()
            }
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
