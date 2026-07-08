import Foundation

/// A single, stateless transformation in the streaming pipeline.
///
/// Conformance requirements (SRP):
/// - Each stage performs exactly one concern.
/// - Stages are immutable / stateless (state lives in `PipelineState` + `PipelineReducer`).
/// - `process()` must be re-entrant-safe (may be called concurrently).
///
/// Conformance requirements (ISP):
/// - Two methods only. Default implementations provided for identity passthrough.
///
/// Thread safety:
/// - The `EventPipeline` serializes events, so stages receive events one-at-a-time.
/// - However, stages should still avoid mutable internal state.
public protocol PipelineStage: AnyObject, Sendable {
    /// Human-readable identifier for debugging and traces.
    var identifier: String { get }

    /// Transform a single incoming event into zero or more outgoing events.
    ///
    /// - Parameter event: The event to process.
    /// - Returns: Events emitted as a result of processing. An empty array
    ///   means this stage swallows the event (e.g. a filter).
    func process(_ event: PipelineEvent) -> [PipelineEvent]

    /// Called when the upstream signals end-of-stream.
    /// Stages that internally buffer data (e.g., argument accumulators)
    /// should flush any pending output here.
    func flush() -> [PipelineEvent]
}

// MARK: - Default implementations

extension PipelineStage {
    /// Default: identity passthrough — emit the event unchanged.
    public func process(_ event: PipelineEvent) -> [PipelineEvent] { [event] }

    /// Default: nothing to flush.
    public func flush() -> [PipelineEvent] { [] }
}

/// A stage that absorbs all events (useful for testing or as a terminal sink).
public final class NullStage: PipelineStage {
    public let identifier = "null"

    public init() {}

    public func process(_ event: PipelineEvent) -> [PipelineEvent] { [] }

    public func flush() -> [PipelineEvent] { [] }
}

/// A stage that logs every event it receives (for debugging / telemetry).
public final class TraceStage: @unchecked Sendable {
    public let identifier = "trace"
    private let onEvent: (PipelineEvent) -> Void

    public init(_ handler: @escaping (PipelineEvent) -> Void) {
        self.onEvent = handler
    }
}

extension TraceStage: PipelineStage {
    public func process(_ event: PipelineEvent) -> [PipelineEvent] {
        onEvent(event)
        return [event]
    }

    public func flush() -> [PipelineEvent] { [] }
}
