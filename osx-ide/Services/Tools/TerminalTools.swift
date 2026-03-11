//
//  TerminalTools.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation
import Darwin

private final class RunCommandOutputBuffer: @unchecked Sendable {
    struct Snapshot {
        let version: Int
        let lastAppendAt: Date?
    }

    private let lock = NSLock()
    private var fullData = Data()
    private var pendingDelta = Data()
    private var version: Int = 0
    private var lastAppendAt: Date?
    private let maxFullBytes: Int
    private let maxDeltaBytes: Int

    init(maxFullBytes: Int = 64 * 1024, maxDeltaBytes: Int = 32 * 1024) {
        self.maxFullBytes = maxFullBytes
        self.maxDeltaBytes = maxDeltaBytes
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        version += 1
        lastAppendAt = Date()

        if chunk.count >= maxFullBytes {
            fullData = Data(chunk.suffix(maxFullBytes))
        } else {
            fullData.append(chunk)
            if fullData.count > maxFullBytes {
                fullData.removeFirst(fullData.count - maxFullBytes)
            }
        }

        if chunk.count >= maxDeltaBytes {
            pendingDelta = Data(chunk.suffix(maxDeltaBytes))
        } else {
            pendingDelta.append(chunk)
            if pendingDelta.count > maxDeltaBytes {
                pendingDelta.removeFirst(pendingDelta.count - maxDeltaBytes)
            }
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(version: version, lastAppendAt: lastAppendAt)
    }

    func consumeDeltaString() -> String {
        lock.lock()
        defer { lock.unlock() }
        defer { pendingDelta.removeAll(keepingCapacity: true) }
        return String(data: pendingDelta, encoding: .utf8) ?? ""
    }

    func fullOutputTailString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: fullData, encoding: .utf8) ?? ""
    }
}

private final class RunCommandSession: @unchecked Sendable {
    let id: String
    let command: String
    let workingDirectory: URL
    let process: Process
    let inputPipe: Pipe
    let outputPipe: Pipe
    let outputBuffer: RunCommandOutputBuffer
    let createdAt: Date

    init(
        id: String,
        command: String,
        workingDirectory: URL,
        process: Process,
        inputPipe: Pipe,
        outputPipe: Pipe,
        outputBuffer: RunCommandOutputBuffer
    ) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.outputBuffer = outputBuffer
        self.createdAt = Date()
    }

    func sendInput(_ text: String) {
        guard process.isRunning else { return }
        guard let data = text.data(using: .utf8), !data.isEmpty else { return }
        inputPipe.fileHandleForWriting.write(data)
    }
}

private actor RunCommandSessionStore {
    struct Observation {
        let status: String
        let reason: String
        let exitCode: Int32?
        let sessionId: String?
        let command: String
        let workingDirectory: String
        let outputDelta: String
        let outputTail: String
        let suggestedWaitSeconds: Int?
    }

    static let shared = RunCommandSessionStore()

    private var sessions: [String: RunCommandSession] = [:]

    func start(
        command: String,
        workingDirectory: URL,
        environment: [String: String]
    ) throws -> RunCommandSession {
        let sessionId = UUID().uuidString
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let outputBuffer = RunCommandOutputBuffer()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = environment
        process.arguments = ["-lc", command]
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.currentDirectoryURL = workingDirectory

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputBuffer.append(data)
        }

        let session = RunCommandSession(
            id: sessionId,
            command: command,
            workingDirectory: workingDirectory,
            process: process,
            inputPipe: inputPipe,
            outputPipe: outputPipe,
            outputBuffer: outputBuffer
        )

        sessions[sessionId] = session
        do {
            try process.run()
        } catch {
            sessions[sessionId] = nil
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        return session
    }

    func observation(
        for sessionId: String,
        waitSeconds: TimeInterval,
        reasonWhenWaitingExpires: String
    ) async throws -> Observation {
        guard let session = sessions[sessionId] else {
            throw AppError.aiServiceError("Unknown run_command session_id '\(sessionId)'. Start a new command instead.")
        }

        let observation = await observe(session: session, waitSeconds: waitSeconds, reasonWhenWaitingExpires: reasonWhenWaitingExpires)
        if observation.status != "running" {
            removeSession(id: session.id)
        }
        return observation
    }

    func sendInput(
        sessionId: String,
        input: String,
        appendNewline: Bool,
        waitSeconds: TimeInterval
    ) async throws -> Observation {
        guard let session = sessions[sessionId] else {
            throw AppError.aiServiceError("Unknown run_command session_id '\(sessionId)'.")
        }

        let payload = appendNewline ? input + "\n" : input
        session.sendInput(payload)
        let observation = await observe(session: session, waitSeconds: waitSeconds, reasonWhenWaitingExpires: "input_wait_elapsed")
        if observation.status != "running" {
            removeSession(id: session.id)
        }
        return observation
    }

    func stop(sessionId: String) async throws -> Observation {
        guard let session = sessions[sessionId] else {
            throw AppError.aiServiceError("Unknown run_command session_id '\(sessionId)'.")
        }

        await terminate(session: session)
        let observation = makeObservation(
            session: session,
            status: "stopped",
            reason: "stopped",
            exitCode: session.process.terminationStatus,
            suggestedWaitSeconds: nil
        )
        removeSession(id: session.id)
        return observation
    }

    private func observe(
        session: RunCommandSession,
        waitSeconds: TimeInterval,
        reasonWhenWaitingExpires: String
    ) async -> Observation {
        let baseline = session.outputBuffer.snapshot()
        let deadline = Date().addingTimeInterval(waitSeconds)
        let settleInterval: TimeInterval = 0.25

        while Date() < deadline {
            if !session.process.isRunning {
                return makeObservation(
                    session: session,
                    status: "exited",
                    reason: "exited",
                    exitCode: session.process.terminationStatus,
                    suggestedWaitSeconds: nil
                )
            }

            let current = session.outputBuffer.snapshot()
            if current.version != baseline.version {
                if let lastAppendAt = current.lastAppendAt,
                   Date().timeIntervalSince(lastAppendAt) >= settleInterval {
                    return makeObservation(
                        session: session,
                        status: "running",
                        reason: "output",
                        exitCode: nil,
                        suggestedWaitSeconds: 30
                    )
                }
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let status = session.process.isRunning ? "running" : "exited"
        let exitCode = status == "running" ? nil : session.process.terminationStatus
        return makeObservation(
            session: session,
            status: status,
            reason: status == "running" ? reasonWhenWaitingExpires : "exited",
            exitCode: exitCode,
            suggestedWaitSeconds: status == "running" ? 30 : nil
        )
    }

    private func makeObservation(
        session: RunCommandSession,
        status: String,
        reason: String,
        exitCode: Int32?,
        suggestedWaitSeconds: Int?
    ) -> Observation {
        Observation(
            status: status,
            reason: reason,
            exitCode: exitCode,
            sessionId: status == "running" ? session.id : nil,
            command: session.command,
            workingDirectory: session.workingDirectory.path,
            outputDelta: session.outputBuffer.consumeDeltaString(),
            outputTail: session.outputBuffer.fullOutputTailString(),
            suggestedWaitSeconds: suggestedWaitSeconds
        )
    }

    private func terminate(session: RunCommandSession) async {
        if session.process.isRunning {
            kill(session.process.processIdentifier, SIGINT)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)

        if session.process.isRunning {
            session.process.terminate()
        }
        try? await Task.sleep(nanoseconds: 500_000_000)

        if session.process.isRunning {
            kill(session.process.processIdentifier, SIGKILL)
        }
    }

    private func removeSession(id: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.outputPipe.fileHandleForReading.readabilityHandler = nil
        try? session.inputPipe.fileHandleForWriting.close()
        try? session.outputPipe.fileHandleForReading.close()
    }
}

/// Run a shell command.
struct RunCommandTool: AIToolProgressReporting {
    private enum Action: String {
        case start
        case wait
        case sendInput = "send_input"
        case stop
    }

    private struct Request {
        let action: Action
        let command: String?
        let sessionId: String?
        let input: String?
        let appendNewline: Bool
        let waitSeconds: TimeInterval
        let workingDirectoryURL: URL?
    }

    let name = "run_command"
    let description = "Execute and control terminal commands through resumable sessions."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "description": "start | wait | send_input | stop. Defaults to start."
                ],
                "command": [
                    "type": "string",
                    "description": "Shell command to execute. Required for action=start."
                ],
                "working_directory": [
                    "type": "string",
                    "description": "Directory to run the command in. Optional for action=start."
                ],
                "session_id": [
                    "type": "string",
                    "description": "Existing run_command session id. Required for wait, send_input, and stop."
                ],
                "input": [
                    "type": "string",
                    "description": "Text to send to the process stdin for action=send_input."
                ],
                "append_newline": [
                    "type": "boolean",
                    "description": "Append a newline after input when action=send_input. Defaults to false."
                ],
                "wait_seconds": [
                    "type": "number",
                    "description": "How long to wait for output or completion before returning control. Defaults: start uses the CLI setting (15s fallback), wait/send_input use 30s."
                ],
                "timeout_seconds": [
                    "type": "number",
                    "description": "Deprecated alias for wait_seconds."
                ]
            ]
        ]
    }

    let projectRoot: URL
    let pathValidator: PathValidator

    func execute(arguments: ToolArguments) async throws -> String {
        try await executeImpl(arguments: arguments.raw)
    }

    func execute(
        arguments: ToolArguments,
        onProgress _: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        try await executeImpl(arguments: arguments.raw)
    }

    private func executeImpl(arguments: [String: Any]) async throws -> String {
        let request = try resolveRequest(arguments: arguments)
        let environment = ProcessInfo.processInfo.environment

        switch request.action {
        case .start:
            guard let command = request.command else {
                throw AppError.aiServiceError("Missing 'command' argument for run_command action=start")
            }
            let workingDirectoryURL = request.workingDirectoryURL ?? projectRoot
            let session = try await RunCommandSessionStore.shared.start(
                command: command,
                workingDirectory: workingDirectoryURL,
                environment: environment
            )
            let observation = try await RunCommandSessionStore.shared.observation(
                for: session.id,
                waitSeconds: request.waitSeconds,
                reasonWhenWaitingExpires: "wait_elapsed"
            )
            return encodeObservation(observation)

        case .wait:
            guard let sessionId = request.sessionId else {
                throw AppError.aiServiceError("Missing 'session_id' argument for run_command action=wait")
            }
            let observation = try await RunCommandSessionStore.shared.observation(
                for: sessionId,
                waitSeconds: request.waitSeconds,
                reasonWhenWaitingExpires: "wait_elapsed"
            )
            return encodeObservation(observation)

        case .sendInput:
            guard let sessionId = request.sessionId else {
                throw AppError.aiServiceError("Missing 'session_id' argument for run_command action=send_input")
            }
            let input = request.input ?? ""
            let observation = try await RunCommandSessionStore.shared.sendInput(
                sessionId: sessionId,
                input: input,
                appendNewline: request.appendNewline,
                waitSeconds: request.waitSeconds
            )
            return encodeObservation(observation)

        case .stop:
            guard let sessionId = request.sessionId else {
                throw AppError.aiServiceError("Missing 'session_id' argument for run_command action=stop")
            }
            let observation = try await RunCommandSessionStore.shared.stop(sessionId: sessionId)
            return encodeObservation(observation)
        }
    }

    private func resolveRequest(arguments: [String: Any]) throws -> Request {
        let action = Action(rawValue: (arguments["action"] as? String ?? "start").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .start
        let command = (arguments["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionId = (arguments["session_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appendNewline = parseBool(arguments["append_newline"]) ?? false
        let waitSeconds = try resolveWaitSeconds(arguments: arguments, action: action)
        let workingDirectoryURL = try resolveWorkingDirectory(arguments: arguments, action: action)

        return Request(
            action: action,
            command: command?.isEmpty == false ? command : nil,
            sessionId: sessionId?.isEmpty == false ? sessionId : nil,
            input: arguments["input"] as? String,
            appendNewline: appendNewline,
            waitSeconds: waitSeconds,
            workingDirectoryURL: workingDirectoryURL
        )
    }

    private func resolveWaitSeconds(arguments: [String: Any], action: Action) throws -> TimeInterval {
        let raw = arguments["wait_seconds"] ?? arguments["timeout_seconds"]
        if let explicit = parseNumber(raw) {
            guard (1...600).contains(explicit) else {
                throw AppError.aiServiceError("Invalid wait_seconds for run_command. Must be between 1 and 600.")
            }
            return explicit
        }

        switch action {
        case .start:
            let stored = UserDefaults.standard.double(forKey: AppConstantsStorage.cliTimeoutSecondsKey)
            let fallback = stored == 0 ? 15 : stored
            return max(1, min(600, fallback))
        case .wait, .sendInput:
            return 30
        case .stop:
            return 1
        }
    }

    private func resolveWorkingDirectory(arguments: [String: Any], action: Action) throws -> URL? {
        guard action == .start else { return nil }
        guard let workingDirectoryArg = arguments["working_directory"] as? String,
              !workingDirectoryArg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return projectRoot
        }
        return try pathValidator.validateAndResolve(workingDirectoryArg)
    }

    private func parseNumber(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as Int32:
            return Double(number)
        case let number as Int64:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func parseBool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func encodeObservation(_ observation: RunCommandSessionStore.Observation) -> String {
        struct Payload: Encodable {
            let command: String
            let exitCode: Int32?
            let outputDelta: String
            let outputTail: String
            let reason: String
            let sessionId: String?
            let status: String
            let suggestedWaitSeconds: Int?
            let workingDirectory: String

            private enum CodingKeys: String, CodingKey {
                case command
                case exitCode = "exit_code"
                case outputDelta = "output_delta"
                case outputTail = "output_tail"
                case reason
                case sessionId = "session_id"
                case status
                case suggestedWaitSeconds = "suggested_wait_seconds"
                case workingDirectory = "working_directory"
            }
        }

        let payload = Payload(
            command: observation.command,
            exitCode: observation.exitCode,
            outputDelta: observation.outputDelta,
            outputTail: observation.outputTail,
            reason: observation.reason,
            sessionId: observation.sessionId,
            status: observation.status,
            suggestedWaitSeconds: observation.suggestedWaitSeconds,
            workingDirectory: observation.workingDirectory
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return """
            {
              "status": "\(observation.status)",
              "reason": "\(observation.reason)"
            }
            """
        }
        return string
    }
}
