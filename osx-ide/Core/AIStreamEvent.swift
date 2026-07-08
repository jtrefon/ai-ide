import Foundation

struct AIStreamEvent: Event {
    let runId: String
    let conversationId: String
    let kind: StreamKind
}

enum StreamKind: Sendable {
    case content(String)
    case reasoning(String)
    case toolCallDelta(AIToolCallDelta)
    case status(StreamStatus)
    case usage(UsageInfo)
    case error(Error)
    case complete(AIServiceResponse)
    case cancelled
}

struct AIToolCallDelta: Sendable {
    let index: Int
    let id: String?
    let name: String?
    let arguments: String?
}

enum StreamStatus: Sendable {
    case started
    case thinking
    case executingTool(String)
    case waiting
    case finished
}
