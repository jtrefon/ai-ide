import Foundation

/// Accumulates tool-call argument fragments across SSE chunks and,
/// at end-of-stream, emits `toolCallCompleted` or `toolCallFailed`
/// for each draft based on JSON parse success.
///
/// This stage replaces the `ChunkCollector`'s argument-accumulation role.
/// In Phase 3+ the final argument parse will be delegated to individual
/// `ToolCallFormatParser` implementations in the registry.
public final class ToolCallAssemblerStage: @unchecked Sendable {
    public let identifier = "tool_call_assembler"
    private var drafts: [String: Draft] = [:]

    public init() {}
}

extension ToolCallAssemblerStage: PipelineStage {

    public func process(_ event: PipelineEvent) -> [PipelineEvent] {
        switch event {
        case .toolCallOpened(let id, let tool):
            drafts[id] = Draft(id: id, tool: tool, accumulated: "")
            return [event]

        case .toolCallArguments(let id, let fragment):
            if var existing = drafts[id] {
                existing.accumulated += fragment
                drafts[id] = existing
            } else {
                // Arguments for an unknown tool call — start a draft
                drafts[id] = Draft(id: id, tool: "unknown", accumulated: fragment)
            }
            return [event]

        case .toolCallCompleted, .toolCallFailed:
            // Already finalized; pass through.
            return [event]

        default:
            return [event]
        }
    }

    public func flush() -> [PipelineEvent] {
        var events = [PipelineEvent]()
        let snapshot = drafts
        drafts.removeAll()

        for (id, draft) in snapshot {
            let trimmed = draft.accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "{}" {
                events.append(.toolCallCompleted(id: id, tool: draft.tool, arguments: [:]))
            } else if let parsed = Self.parseJSONArguments(trimmed) {
                events.append(.toolCallCompleted(id: id, tool: draft.tool, arguments: parsed))
            } else {
                events.append(.toolCallFailed(
                    id: id,
                    tool: draft.tool,
                    rawArguments: trimmed,
                    error: "Invalid JSON at end of stream"
                ))
            }
        }

        return events
    }

    // MARK: - JSON parsing

    private static func parseJSONArguments(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

// MARK: - Internal state

extension ToolCallAssemblerStage {
    private struct Draft: Sendable {
        let id: String
        let tool: String
        var accumulated: String
    }
}
