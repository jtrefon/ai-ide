//
//  TerminalTools.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation
import Darwin

/// Run a shell command
struct RunCommandTool: AIToolProgressReporting {
    private final class AtomicBool: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool
        init(_ value: Bool) { self.value = value }
        func set(_ newValue: Bool) { lock.lock(); defer { lock.unlock() }; value = newValue }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    let name = "run_command"
    let description = "Execute a shell command in the terminal."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": [
                    "type": "string",
                    "description": "The shell command to execute."
                ],
                "working_directory": [
                    "type": "string",
                    "description": "The directory to run the command in (optional)."
                ],
                "timeout_seconds": [
                    "type": "number",
                    "description": "Max seconds to wait before terminating the command (optional; default 30)."
                ]
            ],
            "required": ["command"]
        ]
    }

    let projectRoot: URL
    let pathValidator: PathValidator

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let maxBytes: Int

        init(maxBytes: Int) {
            self.maxBytes = maxBytes
        }

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }

            guard data.count < maxBytes else { return }
            data.append(chunk.prefix(maxBytes - data.count))
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private func executeImpl(
        arguments: [String: Any],
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> String {
        guard let command = arguments["command"] as? String else {
            throw AppError.aiServiceError("Missing 'command' argument for run_command")
        }

        let toolCallId = (arguments["_tool_call_id"] as? String)
            ?? (arguments["toolCallId"] as? String)
            ?? UUID().uuidString
        let isCancelled = AtomicBool(false)

        let observer = makeCancellationObserver(toolCallId: toolCallId, isCancelled: isCancelled)

        defer { NotificationCenter.default.removeObserver(observer) }

        let timeoutSeconds = try resolveTimeoutSeconds(arguments: arguments)
        let workingDirectoryURL = try resolveWorkingDirectory(arguments: arguments)

        let inheritedEnvironment = ProcessInfo.processInfo.environment
        let resolvedPath = inheritedEnvironment["PATH"] ?? ""
        let shellEnv = inheritedEnvironment["SHELL"] ?? ""
        let pathPrefix = String(resolvedPath.prefix(200))
        let commandPreview = String(command.prefix(120))

        await AIToolTraceLogger.shared.log(type: "terminal.run_command", data: [
            "cwd": workingDirectoryURL.path,
            "commandLength": command.count,
            "commandPreview": commandPreview,
            "shell": shellEnv,
            "pathLength": resolvedPath.count,
            "pathPrefix": pathPrefix,
            "timeoutSeconds": timeoutSeconds
        ])

        let maxCapturedBytes = 64 * 1024
        let collector = OutputCollector(maxBytes: maxCapturedBytes)
        let (process, pipe) = makeProcess(
            command: command,
            workingDirectoryURL: workingDirectoryURL,
            inheritedEnvironment: inheritedEnvironment,
            collector: collector,
            onProgress: onProgress
        )

        do {
            try process.run()

            let didExitBeforeTimeout = await waitForExit(
                process: process,
                timeoutSeconds: timeoutSeconds,
                isCancelled: isCancelled
            )

            if isCancelled.get() || !didExitBeforeTimeout {
                await AIToolTraceLogger.shared.log(
                    type: isCancelled.get()
                        ? "terminal.run_command_cancelled"
                        : "terminal.run_command_timeout",
                    data: [
                        "cwd": workingDirectoryURL.path,
                        "commandLength": command.count,
                        "commandPreview": commandPreview,
                        "timeoutSeconds": timeoutSeconds
                    ]
                )
                await terminateProcessIfNeeded(process)
            }

            let output = finalizeOutput(pipe: pipe, collector: collector)

            await AIToolTraceLogger.shared.log(type: "terminal.run_command_result", data: [
                "exitCode": Int(process.terminationStatus),
                "outputLength": output.count,
                "timedOut": !didExitBeforeTimeout,
                "cancelled": isCancelled.get()
            ])

            if isCancelled.get() {
                if onProgress == nil {
                    return "Command cancelled by user.\nPartial Output:\n\(output)"
                }
                return "Command cancelled by user."
            }

            return """
            Exit Code: \(process.terminationStatus)
            Timed Out: \(!didExitBeforeTimeout)
            Output:
            \(output)
            """
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            await AIToolTraceLogger.shared.log(type: "terminal.run_command_error", data: [
                "error": error.localizedDescription
            ])
            return """
            Failed to run command: \(error.localizedDescription)
            """
        }
    }

    private func makeCancellationObserver(toolCallId: String, isCancelled: AtomicBool) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CancelToolExecution"),
            object: nil,
            queue: nil
        ) { notification in
            if let targetId = notification.userInfo?["toolCallId"] as? String, targetId == toolCallId {
                isCancelled.set(true)
            }
        }
    }

    private func resolveTimeoutSeconds(arguments: [String: Any]) throws -> Double {
        let timeoutSecondsRaw = arguments["timeout_seconds"] as? Double
        let timeoutSeconds: Double = {
            if let timeoutSecondsRaw {
                return timeoutSecondsRaw
            }

            let storedTimeout = UserDefaults.standard.double(forKey: AppConstants.Storage.cliTimeoutSecondsKey)
            return storedTimeout == 0 ? 30 : storedTimeout
        }()
        if !(1...300).contains(timeoutSeconds) {
            throw AppError.aiServiceError(
                "Invalid 'timeout_seconds' for run_command. Must be between 1 and 300."
            )
        }
        return timeoutSeconds
    }

    private func resolveWorkingDirectory(arguments: [String: Any]) throws -> URL {
        let workingDirectoryArg = arguments["working_directory"] as? String
        if let workingDirectoryArg, !workingDirectoryArg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try pathValidator.validateAndResolve(workingDirectoryArg)
        }
        return projectRoot
    }

    private func makeProcess(
        command: String,
        workingDirectoryURL: URL,
        inheritedEnvironment: [String: String],
        collector: OutputCollector,
        onProgress: (@Sendable (String) -> Void)?
    ) -> (Process, Pipe) {
        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = inheritedEnvironment
        process.arguments = ["-lc", command]
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.currentDirectoryURL = workingDirectoryURL

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.append(data)
            if let onProgress,
               let chunk = String(data: data, encoding: .utf8),
               !chunk.isEmpty {
                onProgress(chunk)
            }
        }

        return (process, pipe)
    }

    private func waitForExit(
        process: Process,
        timeoutSeconds: Double,
        isCancelled: AtomicBool
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                final class OneShot: @unchecked Sendable {
                    private let lock = NSLock()
                    private var fired = false

                    func fire(_ action: () -> Void) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard !fired else { return }
                        fired = true
                        action()
                    }
                }

                let oneShot = OneShot()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if !process.isRunning {
                        continuation.resume()
                        return
                    }

                    process.terminationHandler = { _ in
                        oneShot.fire {
                            continuation.resume()
                        }
                    }
                }
                return true
            }
            group.addTask {
                let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return false
            }
            group.addTask {
                while !isCancelled.get() {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                return false
            }

            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func terminateProcessIfNeeded(_ process: Process) async {
        if process.isRunning {
            process.terminate()
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func finalizeOutput(pipe: Pipe, collector: OutputCollector) -> String {
        pipe.fileHandleForReading.readabilityHandler = nil
        let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
        collector.append(remaining)
        return String(data: collector.snapshot(), encoding: .utf8) ?? ""
    }

    func execute(arguments: ToolArguments) async throws -> String {
        try await executeImpl(arguments: arguments.raw, onProgress: nil)
    }

    func execute(
        arguments: ToolArguments,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        try await executeImpl(arguments: arguments.raw, onProgress: onProgress)
    }
}
