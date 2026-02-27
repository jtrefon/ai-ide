import Foundation

extension AIToolExecutor {
    struct ToolExecutionCancelledError: LocalizedError, Sendable {
        var errorDescription: String? { "Tool execution cancelled." }
    }

    struct ToolExecutionTimedOutError: LocalizedError, Sendable {
        let timeoutSeconds: Int
        var errorDescription: String? { "Tool execution timed out after \(timeoutSeconds)s." }
    }

    struct ToolExecutionCrashError: LocalizedError, Sendable {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    struct ToolExecutionMessageContext {
        let toolName: String
        let status: ToolExecutionStatus
        let targetFile: String?
        let toolCallId: String
        let preview: String?
    }

    struct ToolProgressSnapshotContext {
        let toolName: String
        let toolCallId: String
        let targetFile: String?
    }

    struct ExecuteToolAndCaptureRequest: @unchecked Sendable {
        let tool: AITool
        let toolCall: AIToolCall
        let mergedArguments: [String: Any]
        let conversationId: String?
        let targetFile: String?
        let onProgress: @MainActor @Sendable (ChatMessage) -> Void
    }

    struct ExecuteToolCallRequest {
        let toolCall: AIToolCall
        let availableTools: [AITool]
        let conversationId: String?
        let onProgress: @MainActor @Sendable (ChatMessage) -> Void
        let targetFile: String?
    }

    nonisolated static func makeToolExecutionMessage(
        content: String,
        context: ToolExecutionMessageContext
    ) -> ChatMessage {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmed.isEmpty ? nil : content
        let message: String

        switch context.status {
        case .executing:
            message = "Tool execution in progress."
        case .completed:
            message = payload == nil
                ? "Tool completed with no payload."
                : "Tool completed successfully."
        case .failed:
            message = trimmed.isEmpty
                ? "Tool failed with no error details."
                : content
        }

        let envelope = ToolExecutionEnvelope(
            status: context.status,
            message: message,
            payload: context.status == .failed ? nil : payload,
            preview: context.preview,
            toolName: context.toolName,
            toolCallId: context.toolCallId,
            targetFile: context.targetFile
        )

        return ChatMessage(
            role: .tool,
            content: envelope.encodedString(),
            tool: ChatMessageToolContext(
                toolName: context.toolName,
                toolStatus: context.status,
                target: ToolInvocationTarget(
                    targetFile: context.targetFile,
                    toolCallId: context.toolCallId
                )
            )
        )
    }

    nonisolated static func sendToolProgressSnapshot(
        snapshot: String,
        context: ToolProgressSnapshotContext,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) {
        Task { @MainActor in
            onProgress(
                Self.makeToolExecutionMessage(
                    content: snapshot,
                    context: ToolExecutionMessageContext(
                        toolName: context.toolName,
                        status: .executing,
                        targetFile: context.targetFile,
                        toolCallId: context.toolCallId,
                        preview: nil
                    )
                )
            )
        }
    }

    nonisolated static func buildInvocationPreview(
        toolName: String,
        targetFile: String?,
        arguments: [String: Any]
    ) -> String? {
        func trim(_ value: String, limit: Int) -> String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count > limit else { return normalized }
            let prefix = normalized.prefix(limit)
            return "\(prefix)\n…"
        }

        func stringArg(_ key: String) -> String? {
            guard let value = arguments[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func intArg(_ key: String) -> Int? {
            if let value = arguments[key] as? Int { return value }
            if let value = arguments[key] as? Int32 { return Int(value) }
            if let value = arguments[key] as? Int64 { return Int(value) }
            if let value = arguments[key] as? Double { return Int(value) }
            if let value = arguments[key] as? NSNumber { return value.intValue }
            if let value = arguments[key] as? String, let parsed = Int(value) { return parsed }
            return nil
        }

        let filePath = targetFile ?? stringArg("path")

        switch toolName {
        case "replace_in_file":
            guard let oldText = stringArg("old_text"), let newText = stringArg("new_text") else {
                return filePath.map { "Edit file: \($0)" }
            }

            let fileLabel = filePath ?? "(unspecified file)"
            return """
            Proposed edit: \(fileLabel)

            --- before
            \(trim(oldText, limit: 700))

            +++ after
            \(trim(newText, limit: 700))
            """

        case "write_file", "create_file":
            guard let content = stringArg("content") else {
                return filePath.map { "Write file: \($0)" }
            }
            let fileLabel = filePath ?? "(unspecified file)"
            return """
            Write file: \(fileLabel)

            \(trim(content, limit: 1400))
            """

        case "delete_file":
            if let filePath {
                return "Delete file: \(filePath)"
            }
            return "Delete file request"

        case "run_command":
            let command = stringArg("command") ?? "(missing command)"
            let workingDirectory = stringArg("working_directory")
            if let workingDirectory {
                return """
                Command: \(trim(command, limit: 280))
                CWD: \(workingDirectory)
                """
            }
            return "Command: \(trim(command, limit: 280))"

        case "read_file":
            let fileLabel = filePath ?? "(unspecified file)"

            let startLine = intArg("start_line") ?? intArg("offset")
            let endLine: Int? = {
                if let explicitEnd = intArg("end_line") {
                    return explicitEnd
                }
                if let startLine, let limit = intArg("limit"), limit > 0 {
                    return startLine + max(0, limit - 1)
                }
                return nil
            }()

            if let startLine, let endLine, endLine >= startLine {
                return "Read file: \(fileLabel)\nLines: \(startLine)-\(endLine)"
            }

            if let startLine {
                return "Read file: \(fileLabel)\nFrom line: \(startLine)"
            }

            return "Read file: \(fileLabel)"

        default:
            if let filePath {
                return "Target file: \(filePath)"
            }
            return nil
        }
    }

    func buildMergedArguments(toolCall: AIToolCall, conversationId: String?) async -> [String: Any] {
        var mergedArguments = toolCall.arguments
        mergedArguments["_tool_call_id"] = toolCall.id
        if let conversationId {
            mergedArguments["_conversation_id"] = conversationId
        }

        let resolvedArguments = await argumentResolver.buildMergedArguments(
            toolCall: toolCall,
            conversationId: conversationId
        )

        for (key, value) in resolvedArguments {
            mergedArguments[key] = value
        }

        return mergedArguments
    }

    func executeToolAndCaptureResult(
        _ request: ExecuteToolAndCaptureRequest
    ) async throws -> String {
        if let streamingTool = request.tool as? any AIToolProgressReporting {
            let toolCallId = request.toolCall.id
            let accumulator = StringAccumulator()
            return try await streamingTool.execute(arguments: ToolArguments(request.mergedArguments)) { chunk in
                let (snapshot, totalLength) = accumulator.appendAndSnapshot(chunk)

                Task { @MainActor in
                    ToolTimeoutCenter.shared.markProgress(toolCallId: toolCallId)
                }

                Task {
                    await self.logToolExecuteProgress(
                        conversationId: request.conversationId,
                        toolCall: request.toolCall,
                        chunk: chunk,
                        totalLength: totalLength
                    )
                }

                Self.sendToolProgressSnapshot(
                    snapshot: snapshot,
                    context: ToolProgressSnapshotContext(
                        toolName: request.toolCall.name,
                        toolCallId: toolCallId,
                        targetFile: request.targetFile
                    ),
                    onProgress: request.onProgress
                )
            }
        }

        return try await request.tool.execute(arguments: ToolArguments(request.mergedArguments))
    }

    func makeToolCallFinalMessage(
        result: Result<String, Error>,
        toolCall: AIToolCall,
        targetFile: String?,
        preview: String?
    ) -> ChatMessage {
        switch result {
        case .success(let content):
            return Self.makeToolExecutionMessage(
                content: content,
                context: ToolExecutionMessageContext(
                    toolName: toolCall.name,
                    status: .completed,
                    targetFile: targetFile,
                    toolCallId: toolCall.id,
                    preview: preview
                )
            )
        case .failure(let error):
            let errorContent = Self.formatError(error, toolName: toolCall.name)
            return Self.makeToolExecutionMessage(
                content: errorContent,
                context: ToolExecutionMessageContext(
                    toolName: toolCall.name,
                    status: .failed,
                    targetFile: targetFile,
                    toolCallId: toolCall.id,
                    preview: preview
                )
            )
        }
    }

    func executeToolCall(
        _ request: ExecuteToolCallRequest
    ) async -> ChatMessage {
        await logToolExecuteStart(
            conversationId: request.conversationId,
            toolCall: request.toolCall,
            targetFile: request.targetFile
        )

        // Begin tool execution activity for power management
        let activityToken = activityCoordinator?.beginActivity(type: .toolExecution)
        
        let resultMessage = await resolveToolAndExecute(request)

        // End tool execution activity
        activityToken?.end()

        Task { @MainActor in
            request.onProgress(resultMessage)
        }

        return resultMessage
    }

    private func resolveToolAndExecute(
        _ request: ExecuteToolCallRequest
    ) async -> ChatMessage {
        guard let tool = resolveTool(for: request.toolCall, from: request.availableTools) else {
            await logToolNotFound(conversationId: request.conversationId, toolCall: request.toolCall)
            return makeToolNotFoundMessage(request)
        }

        let preview = Self.buildInvocationPreview(
            toolName: request.toolCall.name,
            targetFile: request.targetFile,
            arguments: request.toolCall.arguments
        )
        let result = await executeKnownTool(tool, request: request)
        return makeToolCallFinalMessage(
            result: result,
            toolCall: request.toolCall,
            targetFile: request.targetFile,
            preview: preview
        )
    }

    private func resolveTool(for toolCall: AIToolCall, from availableTools: [AITool]) -> AITool? {
        if let directMatch = availableTools.first(where: { $0.name == toolCall.name }) {
            return directMatch
        }

        let aliases: [String: [String]] = [
            "find": ["find_by_name"],
            "grep": ["grep_search"],
            "read": ["read_file"],
            "write": ["write_file", "write_files"],
            "write_files": ["write_file"],
            "create_file": ["write_file", "write_files"],
            "edit_file": ["replace_in_file", "write_file"],
            "run_terminal_command": ["run_command"]
        ]

        guard let candidates = aliases[toolCall.name] else {
            return nil
        }

        for candidate in candidates {
            if let resolved = availableTools.first(where: { $0.name == candidate }) {
                Task {
                    await AIToolTraceLogger.shared.log(
                        type: "tool.alias_resolved",
                        data: [
                            "requested": toolCall.name,
                            "resolved": candidate,
                            "toolCallId": toolCall.id
                        ]
                    )
                }
                return resolved
            }
        }

        return nil
    }

    private func executeKnownTool(
        _ tool: AITool,
        request: ExecuteToolCallRequest
    ) async -> Result<String, Error> {
        let timeoutSeconds = resolveToolTimeoutSeconds()
        await MainActor.run {
            ToolTimeoutCenter.shared.begin(
                toolCallId: request.toolCall.id,
                toolName: request.toolCall.name,
                targetFile: request.targetFile,
                timeoutSeconds: timeoutSeconds
            )
        }

        defer {
            Task { @MainActor in
                ToolTimeoutCenter.shared.finish(toolCallId: request.toolCall.id)
            }
        }
        do {
            let mergedArguments = await buildMergedArguments(
                toolCall: request.toolCall,
                conversationId: request.conversationId
            )

            let content = try await executeToolAndCaptureResultWithWatchdog(
                tool: tool,
                toolCall: request.toolCall,
                mergedArguments: mergedArguments,
                conversationId: request.conversationId,
                targetFile: request.targetFile,
                onProgress: request.onProgress,
                timeoutSeconds: timeoutSeconds
            )
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let error = ToolExecutionCrashError(
                    message: "Tool returned an empty response. Treat this as a crash."
                )
                await logToolExecuteError(
                    conversationId: request.conversationId,
                    toolCall: request.toolCall,
                    error: error
                )
                return .failure(error)
            }

            await logToolExecuteSuccess(
                conversationId: request.conversationId,
                toolCall: request.toolCall,
                resultLength: content.count
            )
            return .success(content)
        } catch {
            await logToolExecuteError(
                conversationId: request.conversationId,
                toolCall: request.toolCall,
                error: error
            )
            return .failure(error)
        }
    }

    private func resolveToolTimeoutSeconds() -> TimeInterval {
        let stored = UserDefaults.standard.double(forKey: AppConstantsStorage.cliTimeoutSecondsKey)
        // Default to 120s for npm operations, up to 600s max
        let normalized = stored == 0 ? 120 : stored
        return max(1, min(600, normalized))
    }

    private func executeToolAndCaptureResultWithWatchdog(
        tool: AITool,
        toolCall: AIToolCall,
        mergedArguments: [String: Any],
        conversationId: String?,
        targetFile: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void,
        timeoutSeconds: TimeInterval
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            let toolTask = Task {
                try await self.executeToolAndCaptureResult(
                    ExecuteToolAndCaptureRequest(
                        tool: tool,
                        toolCall: toolCall,
                        mergedArguments: mergedArguments,
                        conversationId: conversationId,
                        targetFile: targetFile,
                        onProgress: onProgress
                    )
                )
            }

            group.addTask {
                try await toolTask.value
            }

            group.addTask {
                let timeoutSecondsInt = Int(timeoutSeconds)
                
                while true {
                    let (isCancelled, remaining) = await MainActor.run {
                        (
                            ToolTimeoutCenter.shared.isCancelled(toolCallId: toolCall.id),
                            ToolTimeoutCenter.shared.remainingSeconds(toolCallId: toolCall.id)
                        )
                    }
                    if isCancelled {
                        toolTask.cancel()
                        throw ToolExecutionCancelledError()
                    }

                    if let remaining, remaining <= 0 {
                        // Deadline is computed from the most recent progress timestamp.
                        // If we reached it, the tool has made no progress for timeoutSeconds.
                        await MainActor.run {
                            ToolTimeoutCenter.shared.cancel(toolCallId: toolCall.id)
                        }
                        toolTask.cancel()
                        throw ToolExecutionTimedOutError(timeoutSeconds: timeoutSecondsInt)
                    }

                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            }

            let first = try await group.next() ?? ""
            group.cancelAll()
            return first
        }
    }

    private func makeToolNotFoundMessage(
        _ request: ExecuteToolCallRequest
    ) -> ChatMessage {
        Self.makeToolExecutionMessage(
            content: "Tool not found",
            context: ToolExecutionMessageContext(
                toolName: request.toolCall.name,
                status: .failed,
                targetFile: request.targetFile,
                toolCallId: request.toolCall.id,
                preview: nil
            )
        )
    }
}
