import Foundation

extension AIToolExecutor {
    nonisolated static func makeToolExecutionMessage(
        content: String,
        toolName: String,
        status: ToolExecutionStatus,
        targetFile: String?,
        toolCallId: String
    ) -> ChatMessage {
        ChatMessage(
            role: .tool,
            content: content,
            tool: ChatMessageToolContext(
                toolName: toolName,
                toolStatus: status,
                target: ToolInvocationTarget(targetFile: targetFile, toolCallId: toolCallId)
            )
        )
    }

    nonisolated static func sendToolProgressSnapshot(
        snapshot: String,
        toolName: String,
        toolCallId: String,
        targetFile: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) {
        Task { @MainActor in
            onProgress(
                Self.makeToolExecutionMessage(
                    content: snapshot,
                    toolName: toolName,
                    status: .executing,
                    targetFile: targetFile,
                    toolCallId: toolCallId
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
        tool: AITool,
        toolCall: AIToolCall,
        mergedArguments: [String: Any],
        conversationId: String?,
        targetFile: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) async throws -> String {
        if let streamingTool = tool as? any AIToolProgressReporting {
            let toolCallId = toolCall.id
            let accumulator = StringAccumulator()
            return try await streamingTool.execute(arguments: ToolArguments(mergedArguments)) { chunk in
                let (snapshot, totalLength) = accumulator.appendAndSnapshot(chunk)

                Task {
                    await self.logToolExecuteProgress(
                        conversationId: conversationId,
                        toolName: toolCall.name,
                        toolCallId: toolCallId,
                        chunk: chunk,
                        totalLength: totalLength
                    )
                }

                Self.sendToolProgressSnapshot(
                    snapshot: snapshot,
                    toolName: toolCall.name,
                    toolCallId: toolCallId,
                    targetFile: targetFile,
                    onProgress: onProgress
                )
            }
        }

        return try await tool.execute(arguments: ToolArguments(mergedArguments))
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
                toolName: toolCall.name,
                status: .completed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        case .failure(let error):
            let errorContent = Self.formatError(error, toolName: toolCall.name)
            return Self.makeToolExecutionMessage(
                content: errorContent,
                toolName: toolCall.name,
                status: .failed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        }
    }

    func executeToolCall(
        toolCall: AIToolCall,
        availableTools: [AITool],
        conversationId: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void,
        targetFile: String?
    ) async -> ChatMessage {
        await logToolExecuteStart(conversationId: conversationId, toolCall: toolCall, targetFile: targetFile)

        let resultMessage: ChatMessage
        if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
            let result: Result<String, Error>
            do {
                let mergedArguments = await buildMergedArguments(toolCall: toolCall, conversationId: conversationId)
                let content = try await executeToolAndCaptureResult(
                    tool: tool,
                    toolCall: toolCall,
                    mergedArguments: mergedArguments,
                    conversationId: conversationId,
                    targetFile: targetFile,
                    onProgress: onProgress
                )
                await logToolExecuteSuccess(
                    conversationId: conversationId,
                    toolCall: toolCall,
                    resultLength: content.count
                )
                result = .success(content)
            } catch {
                await logToolExecuteError(conversationId: conversationId, toolCall: toolCall, error: error)
                result = .failure(error)
            }

            resultMessage = makeToolCallFinalMessage(result: result, toolCall: toolCall, targetFile: targetFile)
        } else {
            await logToolNotFound(conversationId: conversationId, toolCall: toolCall)
            resultMessage = Self.makeToolExecutionMessage(
                content: "Tool not found",
                toolName: toolCall.name,
                status: .failed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        }

        Task { @MainActor in
            onProgress(resultMessage)
        }

        return resultMessage
    }
}
