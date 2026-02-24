import Foundation

public enum AIRequestStage: String, Codable, Sendable {
    case warmup
    case initial_response
    case strategic_planning
    case tactical_planning
    case tool_loop
    case delivery_gate
    case final_response
    case qa_tool_output_review
    case qa_quality_review
    case other
}

public struct AIServiceHistoryRequest: Sendable {
    public let messages: [ChatMessage]
    public let context: String?
    public let tools: [AITool]?
    public let mode: AIMode?
    public let projectRoot: URL?
    public let runId: String?
    public let stage: AIRequestStage?
    public let conversationId: String?

    public init(
        messages: [ChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?,
        runId: String? = nil,
        stage: AIRequestStage? = nil,
        conversationId: String? = nil
    ) {
        self.messages = messages
        self.context = context
        self.tools = tools
        self.mode = mode
        self.projectRoot = projectRoot
        self.runId = runId
        self.stage = stage
        self.conversationId = conversationId
    }
}
