import Foundation

struct ToolResult: Sendable {
    let toolCall: ParsedToolCall
    let feedback: ToolFeedback
    let startedAt: Date
    let duration: TimeInterval
    let wasInterrupted: Bool
    let workerId: String?

    var succeeded: Bool { feedback.status == .success }
    var failed: Bool { feedback.status == .error }

    func formatted() -> String { ToolFeedbackFormatter().format(feedback) }

    static func success(toolCall: ParsedToolCall, feedback: ToolFeedback, startedAt: Date) -> ToolResult {
        ToolResult(toolCall: toolCall, feedback: feedback, startedAt: startedAt,
                   duration: Date().timeIntervalSince(startedAt), wasInterrupted: false, workerId: nil)
    }
}
