import Foundation

public struct AIServiceResponse: Sendable {
    public let content: String?
    public let toolCalls: [AIToolCall]?
    public let reasoning: String?

    public init(content: String?, toolCalls: [AIToolCall]?, reasoning: String? = nil) {
        self.content = content
        self.toolCalls = toolCalls
        self.reasoning = reasoning
    }
}
