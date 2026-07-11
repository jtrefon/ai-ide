import Foundation

/// A partially or fully parsed tool call from textual model output.
public struct RawToolCall: Sendable {
    public let id: String
    public let name: String
    public let arguments: String  // Raw JSON argument string

    public init(id: String = UUID().uuidString, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// One parser per tool-call wire format (SRP).
///
/// Each concrete parser handles exactly one format family and nothing else.
/// Parsers are stateless (except for optional end-of-stream buffering).
/// They can be called incrementally with partial input.
public protocol ToolCallFormatParser: Sendable {
    /// Unique identifier for debugging and telemetry.
    var formatIdentifier: String { get }

    /// Parse `text` and return any tool calls found, along with the
    /// remaining unparsed text.
    ///
    /// - Parameter text: Raw text to scan for tool-call markup.
    /// - Returns: Parsed tool calls and the leftover text.
    func parse(_ text: String) -> (toolCalls: [RawToolCall], remaining: String)

    /// Called when the stream ends. Returns any buffered partial matches.
    func finalize() -> [RawToolCall]
}

// MARK: - Default implementations

extension ToolCallFormatParser {
    public func finalize() -> [RawToolCall] { [] }
}
