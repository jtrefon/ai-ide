import Foundation

public struct AIServiceHistoryRequest: Sendable {
    public let messages: [ChatMessage]
    public let context: String?
    public let tools: [AITool]?
    public let mode: AIMode?
    public let projectRoot: URL?

    public init(
        messages: [ChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) {
        self.messages = messages
        self.context = context
        self.tools = tools
        self.mode = mode
        self.projectRoot = projectRoot
    }
}
