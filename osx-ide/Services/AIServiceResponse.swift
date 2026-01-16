import Foundation

public struct AIServiceResponse: Sendable {
    public let content: String?
    public let toolCalls: [AIToolCall]?
}
