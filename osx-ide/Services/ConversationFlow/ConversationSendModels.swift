import Foundation

// MARK: - Request and Result Models

struct SendRequest {
    let userInput: String
    let explicitContext: String?
    let mode: AIMode
    let projectRoot: URL
    let conversationId: String
    let runId: String
    let availableTools: [AITool]
    let cancelledToolCallIds: @Sendable () -> Set<String>
    let qaReviewEnabled: Bool

    let assistantStreamingMessageId: UUID?
    let enableAssistantStreaming: Bool
}

struct ToolLoopResult {
    let response: AIServiceResponse
    let lastToolCalls: [AIToolCall]
    let lastToolResults: [ChatMessage]
}

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
