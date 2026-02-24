import Foundation

// Debug test to see actual truncation behavior
let longToolContent = String(repeating: "c", count: 5000)
let messages = [
    ChatMessage(role: .system, content: "You are an assistant"),
    ChatMessage(role: .user, content: "Create a file"),
    ChatMessage(role: .assistant, content: "I'll create that file"),
    ChatMessage(role: .tool, content: longToolContent, tool: ChatMessageToolContext(toolName: "write_file")),
]
]
let result = MessageTruncationPolicy.truncateForModel(messages)
print("Message count: \(result.count)")
for (i, msg) in result.enumerated() {
    print("Message \(i): role=\(msg.role), content length=\(msg.content.count), truncated=\(msg.content.hasSuffix("[truncated]"))")
}
