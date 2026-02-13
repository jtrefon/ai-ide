import Foundation

struct ChatMessageVisibilityPolicy {
    /// Determines if an assistant message should be considered "empty" for filtering purposes.
    /// Draft messages (during streaming) are never considered empty - they should always be visible.
    static func isEmptyAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        
        // Draft messages should always be visible during streaming
        if message.isDraft {
            return false
        }

        let isContentEmpty = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isReasoningEmpty = message.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let isToolCallsEmpty = message.toolCalls?.isEmpty ?? true

        return isContentEmpty && isReasoningEmpty && isToolCallsEmpty
    }
    
    /// Determines if a message should be displayed in the UI.
    /// Draft messages are always displayed, non-draft messages are filtered if empty.
    static func shouldDisplayMessage(_ message: ChatMessage) -> Bool {
        if message.isDraft {
            return true
        }
        return !isEmptyAssistantMessage(message)
    }
}
