import Foundation

/// Converts a single `OpenRouterChatResponseChunk` (SSE delta) into zero
/// or more `PipelineEvent` values.
///
/// This is a **pure function** — no mutable state, no I/O.
/// Call it once per chunk as it arrives from the SSE stream.
enum SSEChunkConverter {

    /// The model/provider identifier used as the `Segment.source`.
    private static let source = "openrouter"

    /// Convert a single SSE chunk into pipeline events.
    /// - Parameter chunk: The decoded SSE delta chunk.
    /// - Returns: Events representing this chunk's contribution.
    static func convert(_ chunk: OpenRouterChatResponseChunk) -> [PipelineEvent] {
        var events = [PipelineEvent]()

        guard let choice = chunk.choices.first else { return events }
        let delta = choice.delta

        // Reasoning (separate channel, e.g. DeepSeek / OpenRouter native reasoning)
        if let reasoning = delta?.reasoning ?? delta?.reasoningContent, !reasoning.isEmpty {
            events.append(.segment(Segment(kind: .reasoning, text: reasoning, source: source)))
        }

        // User-visible content
        if let content = delta?.content, !content.isEmpty {
            events.append(.segment(Segment(kind: .userVisible, text: content, source: source)))
        }

        // Tool calls (SSE delta format)
        if let toolCalls = delta?.toolCalls {
            for toolCall in toolCalls {
                let index = toolCall.index
                // The first chunk for a new index carries id + type + function.name.
                // Subsequent chunks carry only function.arguments fragments.
                if let id = toolCall.id, let name = toolCall.function?.name {
                    events.append(.toolCallOpened(id: id, tool: name, index: index))
                }
                if let args = toolCall.function?.arguments, !args.isEmpty {
                    events.append(.toolCallArguments(id: nil, tool: nil, fragment: args, index: index))
                }
            }
        }

        // Finish reason (stream end signal)
        if let finishReason = choice.finishReason, !finishReason.isEmpty {
            // Optionally convert finish_reason to a status event for telemetry
            events.append(.status(
                provider: source,
                info: PipelineStatusInfo(code: "finish_reason", detail: finishReason)
            ))
            events.append(.finished)
        }

        // Usage info (present on the last chunk)
        if let usage = chunk.usage {
            let detail = "prompt_tokens=\(usage.promptTokens ?? -1) completion_tokens=\(usage.completionTokens ?? -1)"
            events.append(.status(
                provider: source,
                info: PipelineStatusInfo(code: "usage", detail: detail)
            ))
        }

        return events
    }
}

// MARK: - Extended tool call events for index-based tracking

extension PipelineEvent {
    /// A tool call was opened at a specific SSE delta index.
    /// The index identifies which tool call slot within a multi-tool-call batch.
    static func toolCallOpened(id: String, tool: String, index: Int) -> PipelineEvent {
        .toolCallOpened(id: id, tool: tool)
    }

    /// Partial arguments for a tool call at a specific index.
    static func toolCallArguments(id: String? = nil, tool: String? = nil, fragment: String, index: Int) -> PipelineEvent {
        .toolCallArguments(id: id ?? "index_\(index)", fragment: fragment)
    }
}
