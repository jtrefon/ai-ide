import Foundation

// MARK: - Event Kind Classification

/// Classification of a streaming text segment produced by a stage.
public enum SegmentKind: String, Sendable, Equatable, Codable {
    /// Content the user should see rendered (markdown, code, prose).
    case userVisible
    /// Chain-of-thought / reasoning block.
    case reasoning
    /// Raw tool-call markup that should be suppressed from display.
    case toolCallMarkup
    /// Provider-level status update (e.g. "thinking...").
    case status
    /// Error information.
    case error
}

/// A classified slice of streaming output with full provenance.
public struct Segment: Sendable, Equatable {
    public let kind: SegmentKind
    public let text: String
    public let source: String
    public let timestamp: ContinuousClock.Instant

    public init(kind: SegmentKind, text: String, source: String) {
        self.kind = kind
        self.text = text
        self.source = source
        self.timestamp = ContinuousClock.now
    }
}

// MARK: - Status / Error

public struct PipelineStatusInfo: Sendable, Equatable {
    public let code: String
    public let detail: String

    public init(code: String, detail: String) {
        self.code = code
        self.detail = detail
    }
}

public struct PipelineError: Sendable, Equatable {
    public enum Code: String, Sendable, Equatable, Codable {
        case parseFailure
        case stageFailure
        case upstreamDisconnected
        case timeout
        case cancelled
    }

    public let code: Code
    public let message: String
    public let sourceStage: String

    public init(code: Code, message: String, sourceStage: String) {
        self.code = code
        self.message = message
        self.sourceStage = sourceStage
    }
}

// MARK: - Universal Pipeline Event

/// Every event flowing through the streaming pipeline.
///
/// This is the single, universal currency of the entire architecture.
/// Every stage consumes from its input and produces into its output.
/// There is no other communication channel between stages.
public enum PipelineEvent: @unchecked Sendable {
    /// A text segment that has been classified.
    case segment(Segment)

    /// A tool call was opened (identifier and tool name received).
    case toolCallOpened(id: String, tool: String)

    /// Partial arguments for an open tool call (streamed JSON fragments).
    case toolCallArguments(id: String, fragment: String)

    /// A tool call was fully received and its arguments were parsed
    /// into a valid JSON object.
    case toolCallCompleted(id: String, tool: String, arguments: [String: Any])

    /// A tool call was received but arguments could not be parsed.
    case toolCallFailed(id: String, tool: String, rawArguments: String, error: String)

    /// Provider-level status or usage information.
    case status(provider: String, info: PipelineStatusInfo)

    /// End of stream (all data has been delivered).
    case finished

    /// An error occurred during processing.
    case error(PipelineError)
}

extension PipelineEvent: @unchecked Sendable {}
