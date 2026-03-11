import Foundation

// MARK: - Request and Result Models

struct SendRequest {
    let userInput: String
    let mediaAttachments: [ChatMessageMediaAttachment]
    let explicitContext: String?
    let mode: AIMode
    let projectRoot: URL
    let conversationId: String
    let runId: String
    let availableTools: [AITool]
    let cancelledToolCallIds: @Sendable () -> Set<String>
    let qaReviewEnabled: Bool
    let draftAssistantMessageId: UUID?

    init(
        userInput: String,
        mediaAttachments: [ChatMessageMediaAttachment] = [],
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        conversationId: String,
        runId: String,
        availableTools: [AITool],
        cancelledToolCallIds: @escaping @Sendable () -> Set<String>,
        qaReviewEnabled: Bool,
        draftAssistantMessageId: UUID?
    ) {
        self.userInput = userInput
        self.mediaAttachments = mediaAttachments
        self.explicitContext = explicitContext
        self.mode = mode
        self.projectRoot = projectRoot
        self.conversationId = conversationId
        self.runId = runId
        self.availableTools = availableTools
        self.cancelledToolCallIds = cancelledToolCallIds
        self.qaReviewEnabled = qaReviewEnabled
        self.draftAssistantMessageId = draftAssistantMessageId
    }
}

struct ToolLoopResult {
    let response: AIServiceResponse
    let lastToolCalls: [AIToolCall]
    let lastToolResults: [ChatMessage]
}
