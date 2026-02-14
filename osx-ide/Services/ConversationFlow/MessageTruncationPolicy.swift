import Foundation

enum MessageTruncationPolicy {
    static let maxToolResultCharacters = 2000
    static let maxTotalMessageCharacters = 12_000
    private static let truncationSuffix = "\n... [truncated]"

    static func truncateForModel(_ messages: [ChatMessage]) -> [ChatMessage] {
        var truncated = messages.map(truncateToolResult)
        truncated = enforceCharacterBudget(truncated)
        return truncated
    }

    private static func truncateToolResult(_ message: ChatMessage) -> ChatMessage {
        guard message.role == .tool || message.isToolExecution else { return message }
        guard message.content.count > maxToolResultCharacters else { return message }

        let trimmed = String(message.content.prefix(maxToolResultCharacters)) + truncationSuffix
        return ChatMessage(
            id: message.id,
            role: message.role,
            content: trimmed,
            timestamp: message.timestamp,
            context: ChatMessageContentContext(reasoning: message.reasoning, codeContext: message.codeContext),
            tool: ChatMessageToolContext(
                toolName: message.toolName,
                toolStatus: message.toolStatus,
                target: ToolInvocationTarget(targetFile: message.targetFile, toolCallId: message.toolCallId),
                toolCalls: message.toolCalls ?? []
            ),
            isDraft: message.isDraft
        )
    }

    private static func enforceCharacterBudget(_ messages: [ChatMessage]) -> [ChatMessage] {
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        guard totalChars > maxTotalMessageCharacters else { return messages }

        var result = messages
        var currentTotal = totalChars

        for index in result.indices where currentTotal > maxTotalMessageCharacters {
            let msg = result[index]
            guard msg.role == .tool || msg.isToolExecution else { continue }
            guard msg.content.count > 500 else { continue }

            let allowance = 500
            let trimmed = String(msg.content.prefix(allowance)) + truncationSuffix
            currentTotal -= (msg.content.count - trimmed.count)
            result[index] = ChatMessage(
                id: msg.id,
                role: msg.role,
                content: trimmed,
                timestamp: msg.timestamp,
                context: ChatMessageContentContext(reasoning: msg.reasoning, codeContext: msg.codeContext),
                tool: ChatMessageToolContext(
                    toolName: msg.toolName,
                    toolStatus: msg.toolStatus,
                    target: ToolInvocationTarget(targetFile: msg.targetFile, toolCallId: msg.toolCallId),
                    toolCalls: msg.toolCalls ?? []
                ),
                isDraft: msg.isDraft
            )
        }
        return result
    }
}
