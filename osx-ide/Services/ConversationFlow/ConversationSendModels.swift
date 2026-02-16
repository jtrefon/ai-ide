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
    let draftAssistantMessageId: UUID?
}

struct ToolLoopResult {
    let response: AIServiceResponse
    let lastToolCalls: [AIToolCall]
    let lastToolResults: [ChatMessage]
}
