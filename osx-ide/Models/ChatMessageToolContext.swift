import Foundation

public struct ChatMessageToolContext: Sendable {
    public let toolName: String?
    public let toolStatus: ToolExecutionStatus?
    public let targetFile: String?
    public let toolCallId: String?
    public let toolCalls: [AIToolCall]?

    public init(
        toolName: String? = nil,
        toolStatus: ToolExecutionStatus? = nil,
        targetFile: String? = nil,
        toolCallId: String? = nil,
        toolCalls: [AIToolCall]? = nil
    ) {
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.targetFile = targetFile
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
}
