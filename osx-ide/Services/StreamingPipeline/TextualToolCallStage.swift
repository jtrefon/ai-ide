import Foundation

/// Pipeline stage that scans `.userVisible` segments through all registered
/// `ToolCallFormatParser` instances. Tool calls found are emitted as
/// `toolCallOpened` + `toolCallCompleted` events; remaining text is emitted
/// as `.userVisible` segments.
///
/// This stage replaces the ad-hoc `ToolCallFallbackParser` chaining.
/// Every parser lives in its own file, independently testable.
public final class TextualToolCallStage: @unchecked Sendable {
    public let identifier = "textual_tool_call"
    private let registry: ParserRegistry

    public init(registry: ParserRegistry = .default()) {
        self.registry = registry
    }
}

extension TextualToolCallStage: PipelineStage {

    public func process(_ event: PipelineEvent) -> [PipelineEvent] {
        switch event {
        case .segment(let segment) where segment.kind == .userVisible:
            return scanText(segment.text, source: segment.source)
        default:
            return [event]
        }
    }

    public func flush() -> [PipelineEvent] {
        var events = [PipelineEvent]()
        for parser in registry.allParsers() {
            for call in parser.finalize() {
                let args: [String: Any] = parseJSON(call.arguments) ?? [:]
                events.append(.toolCallOpened(id: call.id, tool: call.name))
                events.append(.toolCallCompleted(id: call.id, tool: call.name, arguments: args))
            }
        }
        return events
    }

    private func scanText(_ text: String, source: String) -> [PipelineEvent] {
        var remaining = text
        var events = [PipelineEvent]()

        for parser in registry.allParsers() {
            let (calls, rest) = parser.parse(remaining)
            remaining = rest

            for call in calls {
                let args: [String: Any] = parseJSON(call.arguments) ?? [:]
                events.append(.toolCallOpened(id: call.id, tool: call.name))
                events.append(.toolCallCompleted(id: call.id, tool: call.name, arguments: args))
            }
        }

        // Emit unparsed text as user-visible content
        if !remaining.isEmpty {
            events.append(.segment(Segment(kind: .userVisible, text: remaining, source: source)))
        }

        return events
    }

    private func parseJSON(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }
}
