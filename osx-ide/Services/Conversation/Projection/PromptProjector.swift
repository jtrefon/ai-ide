import Foundation

// MARK: - PromptProjector — builds LLM messages from the immutable log

/// Projects `[Turn]` into `[ProjectedMessage]` suitable for an LLM provider.
///
/// **Protected system/tool block** — injected at projection time, index 0.
/// The system prompt and tool definitions are **never** part of the turn log,
/// so they cannot be reordered or overwritten (Invariant D7).
///
/// **Cache breakpoint** — marks the first user message after the system block
/// so the provider caches the prefix (system + tool defs + context).
/// New turns only append after the breakpoint, keeping the cache warm
/// (Invariant D6, stable prefix).
///
/// **Leak prevention** — tool results are emitted as `role: .tool` messages
/// with a structured summary (never free-text dumps as the assistant's answer).
/// This is the structural fix for the leaked `"Inspected and analyzed: …"`
/// final message (replaces `toolResultsSummaryText` / `compactToolSummaryLines`).
public struct PromptProjector: ConversationProjection {

    public typealias Output = [ProjectedMessage]

    public init() {}

    public func project(_ turns: [Turn], context: ProjectionContext) async -> [ProjectedMessage] {
        var messages = [ProjectedMessage]()
        var cacheBreakpointSet = false

        // --- 1. System + tool block (never in the log) -------------------
        var systemContent = context.systemPrompt
        if !context.toolDefinitions.isEmpty {
            systemContent += "\n\n## Tool Definitions\n" + context.toolDefinitions
        }
        messages.append(ProjectedMessage(role: .system, content: systemContent))

        // --- 2. Conversation turns ---------------------------------------
        for turn in turns {
            let projected = projectTurn(turn)
            for var msg in projected {
                // Set cache breakpoint on the first user message after the system block
                if context.markCacheBreakpoint && !cacheBreakpointSet && msg.role == .user {
                    msg = ProjectedMessage(role: msg.role, content: msg.content, cacheBreakpointAfter: true)
                    cacheBreakpointSet = true
                }
                messages.append(msg)
            }
        }

        return messages
    }

    // MARK: - Turn mapping

    private func projectTurn(_ turn: Turn) -> [ProjectedMessage] {
        switch turn.content {
        case .userText(let text):
            return [ProjectedMessage(role: .user, content: text)]

        case .assistant(let text, let reasoning, let toolCalls):
            var content = ""
            if let r = reasoning, !r.isEmpty {
                content += r + "\n\n"
            }
            content += text
            if !toolCalls.isEmpty {
                let calls = toolCalls.map { call in
                    "- \(call.name)(\(call.argumentsDigest)) [id: \(call.toolCallId)]"
                }.joined(separator: "\n")
                content += "\n\n**Tool calls:**\n" + calls
            }
            return [ProjectedMessage(role: .assistant, content: content)]

        case .toolCall(let summary):
            return [ProjectedMessage(role: .assistant, content: "**Tool call:** \(summary.name)(\(summary.argumentsDigest)) [\(summary.toolCallId)]")]

        case .toolResult(let summary):
            var content = "**Result:** \(summary.name) [\(summary.status)]"
            if let file = summary.targetFile {
                content += " — file: \(file)"
            }
            if let ref = summary.outputRef {
                content += " — output: \(ref)"
            }
            return [ProjectedMessage(role: .tool, content: content)]

        case .systemText(let text):
            return [ProjectedMessage(role: .system, content: text)]

        case .plan(let markdown):
            return [ProjectedMessage(role: .system, content: "**Plan:**\n\(markdown)")]

        case .checkpoint(let summary):
            return [ProjectedMessage(role: .system, content: "**Checkpoint:**\n\(summary)")]
        }
    }
}
