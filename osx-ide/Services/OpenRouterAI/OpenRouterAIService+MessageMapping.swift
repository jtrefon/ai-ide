import Foundation

extension OpenRouterAIService {
    internal static func sanitizeToolCallOrdering(_ messages: [ChatMessage]) -> [ChatMessage] {
        let sanitizer = ToolCallOrderingSanitizer()
        return sanitizer.sanitize(messages)
    }

    internal func buildOpenRouterMessages(from messages: [ChatMessage]) -> [OpenRouterChatMessage] {
        let sanitizedMessages = Self.sanitizeToolCallOrdering(messages)
        let validToolCallIds = buildValidToolCallIds(from: sanitizedMessages)
        // Find the most recent reasoning from any assistant message in this conversation.
        // DeepSeek V4 requires reasoning_content echoed back in every subsequent assistant message.
        let conversationReasoning = sanitizedMessages.last(where: { $0.role == .assistant && ($0.reasoning?.isEmpty == false) })?.reasoning
            ?? lastReasoningContent
        return sanitizedMessages.compactMap { message in
            mapOpenRouterChatMessage(message, validToolCallIds: validToolCallIds, conversationReasoning: conversationReasoning)
        }
    }

    internal func buildValidToolCallIds(from messages: [ChatMessage]) -> Set<String> {
        Set(
            messages
                .compactMap { $0.toolCalls }
                .flatMap { $0 }
                .map { $0.id }
        )
    }

    internal func mapOpenRouterChatMessage(
        _ message: ChatMessage,
        validToolCallIds: Set<String>,
        conversationReasoning: String? = nil
    ) -> OpenRouterChatMessage? {
        switch message.role {
        case .user:
            return OpenRouterChatMessage(role: "user", content: message.content)
        case .assistant:
            let effectiveReasoning = message.reasoning ?? conversationReasoning
            if let toolCalls = message.toolCalls {
                return OpenRouterChatMessage(
                    role: "assistant",
                    content: message.content.isEmpty ? "" : message.content,
                    toolCalls: toolCalls,
                    reasoningContent: effectiveReasoning
                )
            }
            return OpenRouterChatMessage(
                role: "assistant",
                content: message.content,
                reasoningContent: effectiveReasoning
            )
        case .system:
            return OpenRouterChatMessage(role: "system", content: message.content)
        case .tool:
            return mapToolMessage(message, validToolCallIds: validToolCallIds)
        }
    }

    internal func mapToolMessage(
        _ message: ChatMessage,
        validToolCallIds: Set<String>
    ) -> OpenRouterChatMessage? {
        guard message.toolStatus != .executing else { return nil }
        if let toolCallId = message.toolCallId {
            return mapValidToolMessage(message, toolCallId: toolCallId, validToolCallIds: validToolCallIds)
        }
        return mapFallbackToolMessage(message)
    }

    internal func mapValidToolMessage(_ message: ChatMessage, toolCallId: String, validToolCallIds: Set<String>) -> OpenRouterChatMessage? {
        guard validToolCallIds.contains(toolCallId) else { return nil }
        let content = Self.truncate(message.content, limit: Self.maxToolOutputCharsForModel)
        return OpenRouterChatMessage(role: "tool", content: content, toolCallID: toolCallId)
    }

    internal func mapFallbackToolMessage(_ message: ChatMessage) -> OpenRouterChatMessage {
        let content = Self.truncate(message.content, limit: Self.maxToolOutputCharsForModel)
        return OpenRouterChatMessage(role: "user", content: "Tool Output: \(content)")
    }

    internal static func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }
}
