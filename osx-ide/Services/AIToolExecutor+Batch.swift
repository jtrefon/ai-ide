import Foundation

extension AIToolExecutor {
    func executeBatch(
        _ toolCalls: [AIToolCall],
        availableTools: [AITool],
        conversationId: String? = nil,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) async -> [ChatMessage] {
        if toolCalls.isEmpty { return [] }

        var results: [ChatMessage] = []
        results.reserveCapacity(toolCalls.count)

        let tasks: [Task<ChatMessage, Never>] = toolCalls.map {
            makeExecuteBatchTask(
                toolCall: $0,
                availableTools: availableTools,
                conversationId: conversationId,
                onProgress: onProgress
            )
        }

        for task in tasks {
            let message = await task.value
            results.append(message)
        }

        return results
    }

    private func makeExecuteBatchTask(
        toolCall: AIToolCall,
        availableTools: [AITool],
        conversationId: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) -> Task<ChatMessage, Never> {
        let targetFile = resolveTargetFile(for: toolCall)
        emitExecutingProgress(toolCall: toolCall, targetFile: targetFile, onProgress: onProgress)

        return makeScheduledToolExecutionTask(
            ScheduledToolExecutionTaskRequest(
                toolCall: toolCall,
                availableTools: availableTools,
                conversationId: conversationId,
                onProgress: onProgress,
                targetFile: targetFile
            )
        )
    }

    private struct ScheduledToolExecutionTaskRequest {
        let toolCall: AIToolCall
        let availableTools: [AITool]
        let conversationId: String?
        let onProgress: @MainActor @Sendable (ChatMessage) -> Void
        let targetFile: String?
    }

    private func makeScheduledToolExecutionTask(
        _ request: ScheduledToolExecutionTaskRequest
    ) -> Task<ChatMessage, Never> {
        Task { [weak self] in
            guard let self else {
                return Self.makeExecutorUnavailableMessage(toolCall: request.toolCall, targetFile: request.targetFile)
            }

            return await self.executeScheduledToolCall(
                ExecuteScheduledToolCallRequest(
                    toolCall: request.toolCall,
                    availableTools: request.availableTools,
                    conversationId: request.conversationId,
                    onProgress: request.onProgress,
                    targetFile: request.targetFile
                )
            )
        }
    }

    private struct ExecuteScheduledToolCallRequest {
        let toolCall: AIToolCall
        let availableTools: [AITool]
        let conversationId: String?
        let onProgress: @MainActor @Sendable (ChatMessage) -> Void
        let targetFile: String?
    }

    private func runScheduledTask(
        toolCall: AIToolCall,
        pathKey: String,
        work: @escaping @Sendable () async -> ChatMessage
    ) async throws -> ChatMessage {
        if isWriteLikeTool(toolCall.name) {
            return try await scheduler.runWriteTask(pathKey: pathKey) {
                await work()
            }
        }

        return try await scheduler.runReadTask {
            await work()
        }
    }

    private nonisolated static func makeExecuteScheduledFailedMessage(
        toolCall: AIToolCall,
        targetFile: String?,
        error: Error
    ) -> ChatMessage {
        Self.makeToolExecutionMessage(
            content: "Error: \(error.localizedDescription)",
            toolName: toolCall.name,
            status: .failed,
            targetFile: targetFile,
            toolCallId: toolCall.id
        )
    }

    nonisolated private static func makeExecutorUnavailableMessage(
        toolCall: AIToolCall,
        targetFile: String?
    ) -> ChatMessage {
        Self.makeToolExecutionMessage(
            content: "Tool executor unavailable",
            toolName: toolCall.name,
            status: .failed,
            targetFile: targetFile,
            toolCallId: toolCall.id
        )
    }

    private func emitExecutingProgress(
        toolCall: AIToolCall,
        targetFile: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void
    ) {
        let executingMsg = Self.makeToolExecutionMessage(
            content: "Executing \(toolCall.name)...",
            toolName: toolCall.name,
            status: .executing,
            targetFile: targetFile,
            toolCallId: toolCall.id
        )
        onProgress(executingMsg)
    }

    private func executeScheduledToolCall(
        _ request: ExecuteScheduledToolCallRequest
    ) async -> ChatMessage {
        let pathKey = self.pathKey(for: request.toolCall)
        do {
            return try await runScheduledTask(toolCall: request.toolCall, pathKey: pathKey) { [weak self] in
                guard let self else {
                    return Self.makeExecutorUnavailableMessage(toolCall: request.toolCall, targetFile: request.targetFile)
                }

                return await self.executeToolCall(
                    toolCall: request.toolCall,
                    availableTools: request.availableTools,
                    conversationId: request.conversationId,
                    onProgress: request.onProgress,
                    targetFile: request.targetFile
                )
            }
        } catch {
            return Self.makeExecuteScheduledFailedMessage(toolCall: request.toolCall, targetFile: request.targetFile, error: error)
        }
    }
}
