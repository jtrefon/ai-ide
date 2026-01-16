import Foundation

struct AIServiceMessageWithProjectRootRequest: Sendable {
    let message: String
    let context: String?
    let tools: [AITool]?
    let mode: AIMode?
    let projectRoot: URL?
}
