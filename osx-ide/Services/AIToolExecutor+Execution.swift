import Foundation

extension AIToolExecutor {
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
                        toolCallId: context.toolCallId
                    )
                )
            )
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
        targetFile: String?
    ) -> ChatMessage {
        switch result {
        case .success(let content):
            return Self.makeToolExecutionMessage(
                content: content,
                context: ToolExecutionMessageContext(
                    toolName: toolCall.name,
                    status: .completed,
                    targetFile: targetFile,
                    toolCallId: toolCall.id
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
                    toolCallId: toolCall.id
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

        let resultMessage = await resolveToolAndExecute(request)

        Task { @MainActor in
            request.onProgress(resultMessage)
        }

        return resultMessage
    }

    private func resolveToolAndExecute(
        _ request: ExecuteToolCallRequest
    ) async -> ChatMessage {
        guard let tool = request.availableTools.first(where: { $0.name == request.toolCall.name }) else {
            await logToolNotFound(conversationId: request.conversationId, toolCall: request.toolCall)
            return makeToolNotFoundMessage(request)
        }

        let result = await executeKnownTool(tool, request: request)
        return makeToolCallFinalMessage(
            result: result,
            toolCall: request.toolCall,
            targetFile: request.targetFile
        )
    }

    private func executeKnownTool(
        _ tool: AITool,
        request: ExecuteToolCallRequest
    ) async -> Result<String, Error> {
        do {
            let mergedArguments = await buildMergedArguments(
                toolCall: request.toolCall,
                conversationId: request.conversationId
            )
            let content = try await executeToolAndCaptureResult(
                ExecuteToolAndCaptureRequest(
                    tool: tool,
                    toolCall: request.toolCall,
                    mergedArguments: mergedArguments,
                    conversationId: request.conversationId,
                    targetFile: request.targetFile,
                    onProgress: request.onProgress
                )
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

    private func makeToolNotFoundMessage(
        _ request: ExecuteToolCallRequest
    ) -> ChatMessage {
        Self.makeToolExecutionMessage(
            content: "Tool not found",
            context: ToolExecutionMessageContext(
                toolName: request.toolCall.name,
                status: .failed,
                targetFile: request.targetFile,
                toolCallId: request.toolCall.id
            )
        )
    }
}
