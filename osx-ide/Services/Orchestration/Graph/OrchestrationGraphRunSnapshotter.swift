import Foundation

@MainActor
struct OrchestrationGraphRunSnapshotter {
    func appendTransitionSnapshot(nodeId: String, transitionIndex: Int, state: OrchestrationState) async {
        let request = state.request
        let toolCalls = state.response?.toolCalls ?? []
        let toolResults = state.lastToolResults

        let snapshot = OrchestrationRunSnapshot(
            runId: request.runId,
            conversationId: request.conversationId,
            phase: nodeId,
            iteration: transitionIndex,
            timestamp: Date(),
            userInput: request.userInput,
            assistantDraft: state.response?.content,
            failureReason: nil,
            toolCalls: toolCallSummaries(toolCalls),
            toolResults: toolResultSummaries(toolResults)
        )

        try? await OrchestrationRunStore.shared.appendSnapshot(snapshot)
    }

    private func toolCallSummaries(_ toolCalls: [AIToolCall]) -> [OrchestrationRunSnapshot.ToolCallSummary] {
        toolCalls.map {
            OrchestrationRunSnapshot.ToolCallSummary(
                id: $0.id,
                name: $0.name,
                argumentKeys: Array($0.arguments.keys).sorted()
            )
        }
    }

    private func toolResultSummaries(_ toolResults: [ChatMessage]) -> [OrchestrationRunSnapshot.ToolResultSummary] {
        toolResults.compactMap { message in
            guard let toolCallId = message.toolCallId else { return nil }
            return OrchestrationRunSnapshot.ToolResultSummary(
                toolCallId: toolCallId,
                toolName: message.toolName ?? "unknown_tool",
                status: message.toolStatus?.rawValue ?? "unknown",
                targetFile: message.targetFile,
                outputPreview: truncate(toolOutputText(from: message), limit: 1200)
            )
        }
    }

    private func toolOutputText(from message: ChatMessage) -> String {
        guard message.isToolExecution else { return message.content }
        if let envelope = ToolExecutionEnvelope.decode(from: message.content) {
            if let payload = envelope.payload?.trimmingCharacters(in: .whitespacesAndNewlines),
               !payload.isEmpty {
                return payload
            }
            return envelope.message
        }
        return message.content
    }

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }
}
