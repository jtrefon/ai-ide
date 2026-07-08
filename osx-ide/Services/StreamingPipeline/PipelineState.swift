import Foundation

/// Accumulated, observable state of the streaming pipeline.
///
/// This is the "M" in MVI (Model-View-Intent) and the single source of truth
/// for everything the pipeline has processed. It is write-only via
/// `PipelineReducer` and read-only via `toResponse()`.
public struct PipelineState: Sendable {
    /// User-visible content text accumulated so far.
    public var content: String

    /// Reasoning text accumulated so far (chain-of-thought, thinking blocks).
    public var reasoning: String?

    /// Tool-call drafts that are still being streamed (arguments incomplete).
    public var toolCallDrafts: [String: RawToolCallDraft]

    /// Fully received and successfully parsed tool calls.
    public var completedToolCalls: [CompletedToolCall]

    /// Tool calls whose arguments could not be parsed.
    public var malformedToolCalls: [MalformedToolCallRecord]

    /// Provider usage/status info, if available.
    public var status: [String: PipelineStatusInfo]

    /// Whether the stream has ended.
    public var isComplete: Bool

    /// Any error that occurred during processing.
    public var error: PipelineError?

    public init(
        content: String = "",
        reasoning: String? = nil,
        toolCallDrafts: [String: RawToolCallDraft] = [:],
        completedToolCalls: [CompletedToolCall] = [],
        malformedToolCalls: [MalformedToolCallRecord] = [],
        status: [String: PipelineStatusInfo] = [:],
        isComplete: Bool = false,
        error: PipelineError? = nil
    ) {
        self.content = content
        self.reasoning = reasoning
        self.toolCallDrafts = toolCallDrafts
        self.completedToolCalls = completedToolCalls
        self.malformedToolCalls = malformedToolCalls
        self.status = status
        self.isComplete = isComplete
        self.error = error
    }
}

// MARK: - Supporting Types

/// A tool call whose arguments are still being streamed (arguments incomplete).
public struct RawToolCallDraft: Sendable {
    public let id: String
    public let tool: String
    public var accumulatedArguments: String

    public init(id: String, tool: String, accumulatedArguments: String = "") {
        self.id = id
        self.tool = tool
        self.accumulatedArguments = accumulatedArguments
    }
}

/// A fully received and successfully parsed tool call.
public struct CompletedToolCall: @unchecked Sendable {
    public let id: String
    public let tool: String
    public let arguments: [String: Any]

    public init(id: String, tool: String, arguments: [String: Any]) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
    }
}

/// A tool call whose arguments failed to parse.
public struct MalformedToolCallRecord: Sendable {
    public let id: String
    public let tool: String
    public let rawArguments: String
    public let error: String

    public init(id: String, tool: String, rawArguments: String, error: String) {
        self.id = id
        self.tool = tool
        self.rawArguments = rawArguments
        self.error = error
    }
}
