import Foundation
import Combine

/// Adapts `EventPipeline` output into `EventBus` events that the
/// `ConversationManager` already subscribes to.
///
/// This bridge lets the pipeline architecture drive UI streaming without
/// modifying `ConversationManager`'s private methods.
///
/// The adapter publishes:
/// - `LocalModelStreamingChunkEvent` for `.userVisible` segments
/// - `LocalModelStreamingReasoningChunkEvent` for `.reasoning` segments
/// - `LocalModelStreamingStatusEvent` for `.status` segments
///
/// These are the same events the `ConversationManager` already handles
/// for local model streaming — so cloud model streaming now works identically.
@MainActor
public final class StreamingUIAdapter {
    private let eventBus: EventBusProtocol
    private var cancellable: AnyCancellable?
    private var runId: String?

    public init(eventBus: EventBusProtocol) {
        self.eventBus = eventBus
    }

    /// Attach to a pipeline for a specific streaming run.
    public func attach(to pipeline: EventPipeline, runId: String) {
        detach()
        self.runId = runId

        cancellable = pipeline.observe { [weak self] event in
            self?.handle(event)
        }
    }

    /// Detach from the pipeline.
    public func detach() {
        cancellable?.cancel()
        cancellable = nil
        runId = nil
    }

    // MARK: - Event Handling

    private func handle(_ event: PipelineEvent) {
        guard let runId else { return }

        switch event {
        case .segment(let segment):
            switch segment.kind {
            case .userVisible:
                eventBus.publish(LocalModelStreamingChunkEvent(runId: runId, chunk: segment.text))
            case .reasoning:
                eventBus.publish(LocalModelStreamingReasoningChunkEvent(runId: runId, chunk: segment.text))
            case .status:
                eventBus.publish(LocalModelStreamingStatusEvent(
                    runId: runId,
                    message: segment.text
                ))
            case .toolCallMarkup:
                break  // tool markup should not be displayed
            case .error:
                eventBus.publish(LocalModelStreamingStatusEvent(
                    runId: runId,
                    message: "Error: \(segment.text)"
                ))
            }

        case .toolCallCompleted:
            // A tool call is about to execute — flush any pending text
            eventBus.publish(LocalModelStreamingStatusEvent(
                runId: runId,
                message: "Tool call completed: flushing draft"
            ))

        case .finished:
            eventBus.publish(LocalModelStreamingStatusEvent(
                runId: runId,
                message: "Stream complete"
            ))

        default:
            break
        }
    }
}
