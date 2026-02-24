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
    private var ptyPrimaryFD: Int32?
    private var ptySecondaryFD: Int32?

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

        guard validateShellPath(shellPath) else { return }
        guard let pty = createPTY() else {
            notifyError("Failed to create PTY")
            return
        }

        let process = configureProcess(
            ConfigureProcessRequest(
                shellPath: shellPath,
                arguments: arguments,
                directory: directory,
                secondaryHandle: pty.secondaryHandle,
                environmentOverrides: environmentOverrides
            )
        )

        registerRunningProcess(process, pty: pty)
        setupOutputMonitoring()
        launchProcessAndFinalize(process, pty: pty)
    }

    private func validateShellPath(_ shellPath: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            notifyError("Shell at \(shellPath) is not executable")
            return false
        }
        return true
    }

    private func launchProcessAndFinalize(_ process: Process, pty: PTYHandles) {
        do {
            try process.run()
            finalizeStartAfterRun(secondaryHandle: pty.secondaryHandle)
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
        let primaryFD: Int32
        let secondaryFD: Int32
        let primaryHandle: FileHandle
        let secondaryHandle: FileHandle
    }

    private func createPTY() -> PTYHandles? {
        var primary: Int32 = 0
        var secondary: Int32 = 0
        guard openpty(&primary, &secondary, nil, nil, nil) == 0 else {
            return nil
        }

        var winSize = winsize(
            ws_row: UInt16(AppConstantsTerminal.defaultRows),
            ws_col: UInt16(AppConstantsTerminal.defaultColumns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(primary, TIOCSWINSZ, &winSize)

        return PTYHandles(
            primaryFD: primary,
            secondaryFD: secondary,
            primaryHandle: FileHandle(fileDescriptor: primary, closeOnDealloc: false),
            secondaryHandle: FileHandle(fileDescriptor: secondary, closeOnDealloc: false)
        )
    }

    private struct ConfigureProcessRequest {
        let shellPath: String
        let arguments: [String]
        let directory: URL?
        let secondaryHandle: FileHandle
        let environmentOverrides: [String: String]
    }

    private func configureProcess(_ request: ConfigureProcessRequest) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.shellPath)
        process.arguments = request.arguments
        process.currentDirectoryURL = request.directory ?? FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = request.secondaryHandle
        process.standardOutput = request.secondaryHandle
        process.standardError = request.secondaryHandle
        process.environment = Self.buildEnvironment(environmentOverrides: request.environmentOverrides)
        return process
    }

    private func registerRunningProcess(_ process: Process, pty: PTYHandles) {
        shellProcess = process
        ptyPrimaryFD = pty.primaryFD
        ptySecondaryFD = pty.secondaryFD
        readHandle = pty.primaryHandle
        writeHandle = pty.primaryHandle
    }

    nonisolated static func buildEnvironment(environmentOverrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = environmentOverrides["TERM"] ?? "xterm-256color"
        environment["COLUMNS"] = environmentOverrides["COLUMNS"] ?? "\(AppConstantsTerminal.defaultColumns)"
        environment["LINES"] = environmentOverrides["LINES"] ?? "\(AppConstantsTerminal.defaultRows)"

        if environment["HOME"]?.isEmpty ?? true {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }

        if environmentOverrides["PROMPT_EOL_MARK"] == nil {
            environment["PROMPT_EOL_MARK"] = ""
        }
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        return environment
    }

    private func finalizeStartAfterRun(secondaryHandle: FileHandle) {
        try? secondaryHandle.close()
        ptySecondaryFD = nil
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
                Task {
                    await CrashReporter.shared.capture(
                        error,
                        context: CrashReportContext(operation: "ShellManager.sendInput"),
                        metadata: [:],
                        file: #fileID,
                        function: #function,
                        line: #line
                    )
                }
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

    /// Resize the PTY window
    func resize(rows: Int, columns: Int) {
        guard let primaryFD = ptyPrimaryFD else { return }
        
        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(primaryFD, TIOCSWINSZ, &winSize)
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
        ptyPrimaryFD = nil
        ptySecondaryFD = nil
    }

    private func notifyError(_ message: String) {
        Task { @MainActor in
            self.delegate?.shellManager(self, didFailWithError: message)
        }
    }
}
