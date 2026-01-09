import Foundation

public struct ExecutionLogEvent: Codable, Sendable {
    public let ts: String
    public let session: String
    public let conversationId: String?
    public let tool: String
    public let toolCallId: String
    public let type: String
    public let data: [String: LogValue]

    public init(
        ts: String,
        session: String,
        conversationId: String?,
        tool: String,
        toolCallId: String,
        type: String,
        data: [String: LogValue] = [:]
    ) {
        self.ts = ts
        self.session = session
        self.conversationId = conversationId
        self.tool = tool
        self.toolCallId = toolCallId
        self.type = type
        self.data = data
    }
}
