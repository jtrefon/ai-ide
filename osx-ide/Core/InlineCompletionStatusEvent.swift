import Foundation

public enum InlineCompletionStatus: String, Sendable {
    case idle
    case generating
    case noSuggestion
}

public struct InlineCompletionStatusEvent: Event {
    public let status: InlineCompletionStatus

    public init(status: InlineCompletionStatus) {
        self.status = status
    }
}
