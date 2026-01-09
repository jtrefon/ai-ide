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
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String else {
            throw AppError.aiServiceError("Missing 'command' argument for run_command")
        }

        let toolCallId = (arguments["_tool_call_id"] as? String)
            ?? (arguments["toolCallId"] as? String)
            ?? UUID().uuidString
        let isCancelled = AtomicBool(false)
        
        let observer = NotificationCenter.default.addObserver(forName: NSNotification.Name("CancelToolExecution"), object: nil, queue: nil) { notification in
            if let targetId = notification.userInfo?["toolCallId"] as? String, targetId == toolCallId {
                isCancelled.set(true)
            }
        }
        
        defer { NotificationCenter.default.removeObserver(observer) }

        let timeoutSecondsRaw = arguments["timeout_seconds"] as? Double
        let timeoutSeconds = timeoutSecondsRaw ?? 30
        if !(1...300).contains(timeoutSeconds) {
            throw AppError.aiServiceError("Invalid 'timeout_seconds' for run_command. Must be between 1 and 300.")
        }
        
        let workingDirectoryArg = arguments["working_directory"] as? String
        let workingDirectoryURL: URL
        if let workingDirectoryArg, !workingDirectoryArg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workingDirectoryURL = try pathValidator.validateAndResolve(workingDirectoryArg)
        } else {
            workingDirectoryURL = projectRoot
        }

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
        
        let process = Process()
        let pipe = Pipe()
        let maxCapturedBytes = 64 * 1024
        let collector = OutputCollector(maxBytes: maxCapturedBytes)
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = inheritedEnvironment

        // Use a login shell so PATH matches the user's terminal (nvm/asdf/homebrew, etc.)
        process.arguments = ["-lc", command]
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        process.currentDirectoryURL = workingDirectoryURL

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.append(data)
        }
        
        do {
            try process.run()

            let didExitBeforeTimeout: Bool = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                            if !process.isRunning || isCancelled.get() {
                                timer.invalidate()
                                continuation.resume()
                            }
                        }
                        RunLoop.main.add(timer, forMode: .common)
                    }
                    return true
                }
                group.addTask {
                    let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    return false
                }

                let first = await group.next() ?? false
                
                if isCancelled.get() {
                    process.terminate()
                    return false
                }
                
                group.cancelAll()
                return first
            }

            if isCancelled.get() || !didExitBeforeTimeout {
                await AIToolTraceLogger.shared.log(type: isCancelled.get() ? "terminal.run_command_cancelled" : "terminal.run_command_timeout", data: [
                    "cwd": workingDirectoryURL.path,
                    "commandLength": command.count,
                    "commandPreview": commandPreview,
                    "timeoutSeconds": timeoutSeconds
                ])

                if process.isRunning {
                    process.terminate()
                }

                // Give it a short grace period, then SIGKILL if still running.
                try? await Task.sleep(nanoseconds: 500_000_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            collector.append(remaining)
            
            let output = String(data: collector.snapshot(), encoding: .utf8) ?? ""

            await AIToolTraceLogger.shared.log(type: "terminal.run_command_result", data: [
                "exitCode": Int(process.terminationStatus),
                "outputLength": output.count,
                "timedOut": !didExitBeforeTimeout,
                "cancelled": isCancelled.get()
            ])
            
            if isCancelled.get() {
                return "Command cancelled by user.\nPartial Output:\n\(output)"
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

    func execute(
        arguments: [String: Any],
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        guard let command = arguments["command"] as? String else {
            throw AppError.aiServiceError("Missing 'command' argument for run_command")
        }

        let toolCallId = (arguments["_tool_call_id"] as? String)
            ?? (arguments["toolCallId"] as? String)
            ?? UUID().uuidString
        let isCancelled = AtomicBool(false)

        let observer = NotificationCenter.default.addObserver(forName: NSNotification.Name("CancelToolExecution"), object: nil, queue: nil) { notification in
            if let targetId = notification.userInfo?["toolCallId"] as? String, targetId == toolCallId {
                isCancelled.set(true)
            }
        }

        defer { NotificationCenter.default.removeObserver(observer) }

        let timeoutSecondsRaw = arguments["timeout_seconds"] as? Double
        let timeoutSeconds = timeoutSecondsRaw ?? 30
        if !(1...300).contains(timeoutSeconds) {
            throw AppError.aiServiceError("Invalid 'timeout_seconds' for run_command. Must be between 1 and 300.")
        }

        let workingDirectoryArg = arguments["working_directory"] as? String
        let workingDirectoryURL: URL
        if let workingDirectoryArg, !workingDirectoryArg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workingDirectoryURL = try pathValidator.validateAndResolve(workingDirectoryArg)
        } else {
            workingDirectoryURL = projectRoot
        }

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

        let process = Process()
        let pipe = Pipe()
        let maxCapturedBytes = 64 * 1024
        let collector = OutputCollector(maxBytes: maxCapturedBytes)

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
            if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                onProgress(chunk)
            }
        }

        do {
            try process.run()

            let didExitBeforeTimeout: Bool = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                            if !process.isRunning || isCancelled.get() {
                                timer.invalidate()
                                continuation.resume()
                            }
                        }
                        RunLoop.main.add(timer, forMode: .common)
                    }
                    return true
                }
                group.addTask {
                    let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    return false
                }

                let first = await group.next() ?? false

                if isCancelled.get() {
                    process.terminate()
                    return false
                }

                group.cancelAll()
                return first
            }

            if isCancelled.get() || !didExitBeforeTimeout {
                await AIToolTraceLogger.shared.log(type: isCancelled.get() ? "terminal.run_command_cancelled" : "terminal.run_command_timeout", data: [
                    "cwd": workingDirectoryURL.path,
                    "commandLength": command.count,
                    "commandPreview": commandPreview,
                    "timeoutSeconds": timeoutSeconds
                ])

                if process.isRunning {
                    process.terminate()
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            collector.append(remaining)

            let output = String(data: collector.snapshot(), encoding: .utf8) ?? ""

            await AIToolTraceLogger.shared.log(type: "terminal.run_command_result", data: [
                "exitCode": Int(process.terminationStatus),
                "outputLength": output.count,
                "timedOut": !didExitBeforeTimeout,
                "cancelled": isCancelled.get()
            ])

            if isCancelled.get() {
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
}
