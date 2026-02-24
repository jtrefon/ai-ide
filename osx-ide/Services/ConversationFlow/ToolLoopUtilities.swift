import Foundation

/// Shared utility functions for tool loop processing across handlers.
/// This eliminates code duplication between ToolLoopHandler, QAReviewHandler,
/// FinalResponseHandler, and ConversationSendCoordinator.
enum ToolLoopUtilities {
    // MARK: - Text Processing
    
    /// Truncates text to a specified limit with a truncation marker.
    /// - Parameters:
    ///   - text: The text to truncate
    ///   - limit: Maximum character limit
    /// - Returns: Truncated text with "[TRUNCATED]" marker if needed
    static func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }
    
    // MARK: - Tool Output Processing
    
    /// Extracts the relevant text from a tool message.
    /// Handles both regular messages and tool execution envelopes.
    /// - Parameter message: The chat message to extract text from
    /// - Returns: The relevant text content
    static func toolOutputText(from message: ChatMessage) -> String {
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
    
    /// Builds a summary text from tool results.
    /// - Parameter toolResults: Array of tool result messages
    /// - Returns: Formatted summary string
    static func toolResultsSummaryText(_ toolResults: [ChatMessage]) -> String {
        let lines = toolResults.compactMap { message -> String? in
            guard let toolCallId = message.toolCallId else { return nil }
            let status = message.toolStatus?.rawValue ?? "unknown"
            let preview = truncate(toolOutputText(from: message), limit: ToolLoopConstants.toolResultPreviewLimit)
            return "- \(message.toolName ?? "unknown_tool") (\(toolCallId)) [\(status)]: \(preview)"
        }
        return lines.isEmpty ? "No tool outputs." : lines.joined(separator: "\n")
    }
    
    // MARK: - Snapshot Building
    
    /// Creates tool call summaries for orchestration snapshots.
    /// - Parameter toolCalls: Array of tool calls to summarize
    /// - Returns: Array of tool call summaries
    static func toolCallSummaries(_ toolCalls: [AIToolCall]) -> [OrchestrationRunSnapshot.ToolCallSummary] {
        toolCalls.map {
            OrchestrationRunSnapshot.ToolCallSummary(
                id: $0.id,
                name: $0.name,
                argumentKeys: Array($0.arguments.keys).sorted()
            )
        }
    }
    
    /// Creates tool result summaries for orchestration snapshots.
    /// - Parameter toolResults: Array of tool result messages
    /// - Returns: Array of tool result summaries
    static func toolResultSummaries(_ toolResults: [ChatMessage]) -> [OrchestrationRunSnapshot.ToolResultSummary] {
        toolResults.compactMap { message in
            guard let toolCallId = message.toolCallId else { return nil }
            let output = toolOutputText(from: message)
            return OrchestrationRunSnapshot.ToolResultSummary(
                toolCallId: toolCallId,
                toolName: message.toolName ?? "unknown_tool",
                status: message.toolStatus?.rawValue ?? "unknown",
                targetFile: message.targetFile,
                outputPreview: truncate(output, limit: ToolLoopConstants.toolOutputSnapshotLimit)
            )
        }
    }
    
    /// Extracts failure reasons from tool results.
    /// - Parameter toolResults: Array of tool result messages
    /// - Returns: Failure summary string if any failures exist
    static func failureReason(from toolResults: [ChatMessage]) -> String? {
        let failures = toolResults.filter { $0.isToolExecution && $0.toolStatus == .failed }
        guard !failures.isEmpty else { return nil }
        let summary = failures.compactMap { message -> String? in
            guard let toolCallId = message.toolCallId else { return nil }
            let preview = truncate(toolOutputText(from: message), limit: ToolLoopConstants.failurePreviewLimit)
            return "\(message.toolName ?? "unknown_tool") (\(toolCallId)): \(preview)"
        }
        return summary.joined(separator: "\n")
    }
    
    // MARK: - Snapshot Persistence
    
    /// Appends a run snapshot to the orchestration store.
    /// - Parameter payload: The snapshot payload to append
    static func appendRunSnapshot(payload: RunSnapshotPayload) async {
        let snapshot = OrchestrationRunSnapshot(
            runId: payload.runId,
            conversationId: payload.conversationId,
            phase: payload.phase,
            iteration: payload.iteration,
            timestamp: Date(),
            userInput: payload.userInput,
            assistantDraft: payload.assistantDraft,
            failureReason: payload.failureReason,
            toolCalls: toolCallSummaries(payload.toolCalls),
            toolResults: toolResultSummaries(payload.toolResults)
        )
        try? await OrchestrationRunStore.shared.appendSnapshot(snapshot)
    }
    
    /// Convenience method to append a run snapshot with individual parameters.
    /// - Parameters: Individual snapshot fields
    static func appendRunSnapshot(
        runId: String,
        conversationId: String,
        phase: String,
        iteration: Int?,
        userInput: String,
        assistantDraft: String?,
        failureReason: String?,
        toolCalls: [AIToolCall],
        toolResults: [ChatMessage]
    ) async {
        let payload = RunSnapshotPayload(
            runId: runId,
            conversationId: conversationId,
            phase: phase,
            iteration: iteration,
            userInput: userInput,
            assistantDraft: assistantDraft,
            failureReason: failureReason,
            toolCalls: toolCalls,
            toolResults: toolResults
        )
        await appendRunSnapshot(payload: payload)
    }
}

// MARK: - Run Snapshot Payload

/// Data payload for creating orchestration run snapshots.
struct RunSnapshotPayload {
    let runId: String
    let conversationId: String
    let phase: String
    let iteration: Int?
    let userInput: String
    let assistantDraft: String?
    let failureReason: String?
    let toolCalls: [AIToolCall]
    let toolResults: [ChatMessage]
}
