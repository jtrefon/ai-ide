import Foundation
import Combine

/// Terminal pipeline stage that accumulates `PipelineState` via the
/// pure-function `PipelineReducer`.
///
/// This stage replaces the ad-hoc `StreamingOutputBuffer` and the
/// implicit state accumulation currently scattered across
/// `ChunkCollector`, `AIServiceResponse` assembly, and `StreamingUIAdapter`.
///
/// SRP: This stage does ONLY state accumulation via the reducer.
/// It does NOT transform events — it passes them through unchanged
/// so that downstream observers (UI adapter, final assembly) receive them.
///
/// CQRS: Write path = `PipelineReducer.reduce()` (pure function).
/// Read path = `state` property (immutable snapshot).
public final class BufferCoordinatorStage: @unchecked Sendable {
    public let identifier = "buffer_coordinator"

    /// The current accumulated state. Read-only from outside this stage.
    public private(set) var state: PipelineState

    /// Publisher for state changes (for Combine-based observation).
    private let stateSubject = PassthroughSubject<PipelineState, Never>()

    public init(initial: PipelineState = PipelineState()) {
        self.state = initial
    }
}

// MARK: - PipelineStage conformance

extension BufferCoordinatorStage: PipelineStage {

    public func process(_ event: PipelineEvent) -> [PipelineEvent] {
        let newState = PipelineReducer.reduce(state: state, event: event)
        state = newState
        stateSubject.send(newState)
        return [event]
    }

    public func flush() -> [PipelineEvent] {
        // At end of stream, any remaining pending tool call drafts
        // should have been handled by upstream stages (ToolCallAssemblerStage).
        // We emit the final state as a status event for telemetry.
        let info = PipelineStatusInfo(
            code: "pipeline_complete",
            detail: "content_len=\(state.content.count) tools=\(state.completedToolCalls.count)"
        )
        return [.status(provider: identifier, info: info)]
    }
}

// MARK: - Combine observation

extension BufferCoordinatorStage {
    /// Subscribe to state changes via Combine.
    public var statePublisher: AnyPublisher<PipelineState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    /// Access the current state snapshot synchronously.
    public var currentState: PipelineState { state }
}
