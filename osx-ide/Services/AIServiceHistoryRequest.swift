import Foundation

struct AIServiceHistoryRequest: Sendable {
    let messages: [ChatMessage]
    let context: String?
    let tools: [AITool]?
    let mode: AIMode?
    let projectRoot: URL?
}
