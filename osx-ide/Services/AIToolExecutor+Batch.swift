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
            toolCall: toolCall,
            availableTools: availableTools,
            conversationId: conversationId,
            onProgress: onProgress,
            targetFile: targetFile
        )
    }

    private func makeScheduledToolExecutionTask(
        toolCall: AIToolCall,
        availableTools: [AITool],
        conversationId: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void,
        targetFile: String?
    ) -> Task<ChatMessage, Never> {
        Task { [weak self] in
            guard let self else {
                return Self.makeExecutorUnavailableMessage(toolCall: toolCall, targetFile: targetFile)
            }

            return await self.executeScheduledToolCall(
                toolCall: toolCall,
                availableTools: availableTools,
                conversationId: conversationId,
                onProgress: onProgress,
                targetFile: targetFile
            )
        }
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
        toolCall: AIToolCall,
        availableTools: [AITool],
        conversationId: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void,
        targetFile: String?
    ) async -> ChatMessage {
        let pathKey = self.pathKey(for: toolCall)
        let run = makeToolCallRunner(
            toolCall: toolCall,
            availableTools: availableTools,
            conversationId: conversationId,
            onProgress: onProgress,
            targetFile: targetFile
        )

        do {
            if isWriteLikeTool(toolCall.name) {
                return try await scheduler.runWriteTask(pathKey: pathKey) {
                    await run()
                }
            }

            return try await scheduler.runReadTask {
                await run()
            }
        } catch {
            return Self.makeToolExecutionMessage(
                content: "Error: \(error.localizedDescription)",
                toolName: toolCall.name,
                status: .failed,
                targetFile: targetFile,
                toolCallId: toolCall.id
            )
        }
    }

    private func makeToolCallRunner(
        toolCall: AIToolCall,
        availableTools: [AITool],
        conversationId: String?,
        onProgress: @MainActor @Sendable @escaping (ChatMessage) -> Void,
        targetFile: String?
    ) -> @Sendable () async -> ChatMessage {
        { [weak self] in
            guard let self else {
                return Self.makeExecutorUnavailableMessage(toolCall: toolCall, targetFile: targetFile)
            }

            return await self.executeToolCall(
                toolCall: toolCall,
                availableTools: availableTools,
                conversationId: conversationId,
                onProgress: onProgress,
                targetFile: targetFile
            )
        }
    }
}
