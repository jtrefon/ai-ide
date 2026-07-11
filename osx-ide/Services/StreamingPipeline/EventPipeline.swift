import Foundation
import Combine

/// A linearly composed chain of `PipelineStage` values.
///
/// Events flow sequentially from the source through each stage:
///
/// ```
/// ingest(event)
///   → stages[0].process(event)  → [out_0_0, out_0_1, …]
///     → stages[1].process(out_0_0) → [out_1_0, …]
///     → stages[1].process(out_0_1) → [out_1_0, …]
///       → …
///         → subscribers.forEach { $0(finalEvent) }
/// ```
///
/// Thread safety:
/// - `ingest()` and `finish()` are serialized via an internal actor-like lock.
/// - Subscriber callbacks run on the calling thread; dispatch to a specific
///   queue is the subscriber's responsibility.
///
/// OCP: Add processing steps by inserting new stages, not by modifying existing ones.
public final class EventPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [PipelineStage]
    private var subscriberBoxes: [HandlerBox] = []
    private var hasFinished = false

    /// Create a pipeline with an optional initial set of stages.
    public init(stages: [PipelineStage] = []) {
        self.stages = stages
    }

    // MARK: - Topology Mutation

    /// Append a stage to the end of the chain.
    public func append(_ stage: PipelineStage) {
        lock.withLock { stages.append(stage) }
    }

    /// Insert a stage directly after a specific predecessor.
    /// If `predecessor` is not in the chain, the stage is appended.
    public func insert(_ stage: PipelineStage, after predecessor: PipelineStage) {
        lock.withLock {
            guard let index = stages.firstIndex(where: { $0 === predecessor }) else {
                stages.append(stage)
                return
            }
            stages.insert(stage, at: index + 1)
        }
    }

    /// Remove the first occurrence of a stage from the chain.
    public func remove(_ stage: PipelineStage) {
        lock.withLock {
            stages.removeAll { $0 === stage }
        }
    }

    /// Replace the first occurrence of `old` with `new`.
    /// If `old` is not in the chain, `new` is appended.
    public func replace(_ old: PipelineStage, with new: PipelineStage) {
        lock.withLock {
            guard let index = stages.firstIndex(where: { $0 === old }) else {
                stages.append(new)
                return
            }
            stages[index] = new
        }
    }

    // MARK: - Execution

    /// Feed a single event into the pipeline.
    /// Events are serialized — only one event is processed at a time.
    public func ingest(_ event: PipelineEvent) {
        let currentStages: [PipelineStage] = lock.withLock { stages }
        propagate(event, through: currentStages)
    }

    /// Feed multiple events into the pipeline.
    public func ingest<S: Sequence>(_ events: S) where S.Element == PipelineEvent {
        let currentStages: [PipelineStage] = lock.withLock { stages }
        for event in events {
            propagate(event, through: currentStages)
        }
    }

    /// Signal end-of-stream to all stages, then flush them.
    public func finish() {
        let currentStages: [PipelineStage] = lock.withLock {
            guard !hasFinished else { return [PipelineStage]() }
            hasFinished = true
            return stages
        }
        guard !currentStages.isEmpty else { return }

        var flushingEvents = [PipelineEvent]()
        for stage in currentStages {
            flushingEvents.append(contentsOf: stage.flush())
        }
        flushingEvents.append(.finished)

        for event in flushingEvents {
            notifySubscribers(event)
        }
    }

    // MARK: - Observation

    /// Subscribe to every event that emerges from the pipeline.
    /// - Parameter handler: Called for each output event.
    /// - Returns: A `AnyCancellable` that, when deallocated, removes the subscription.
    @discardableResult
    public func observe(_ handler: @escaping (PipelineEvent) -> Void) -> AnyCancellable {
        let box = HandlerBox(handler)
        lock.withLock { subscriberBoxes.append(box) }
        return AnyCancellable { [weak self] in
            self?.lock.withLock {
                self?.subscriberBoxes.removeAll { $0 === box }
            }
        }
    }

    /// Subscribe to events of a specific case (via pattern match).
    /// Only events that match `transform` are forwarded.
    @discardableResult
    public func observe(_ matching: @escaping (PipelineEvent) -> PipelineEvent?,
                        handler: @escaping (PipelineEvent) -> Void) -> AnyCancellable {
        observe { event in
            if let matched = matching(event) {
                handler(matched)
            }
        }
    }

    // MARK: - Private

    private func propagate(_ event: PipelineEvent, through chain: [PipelineStage]) {
        var events = [event]
        for stage in chain {
            var next: [PipelineEvent] = []
            for ev in events {
                next.append(contentsOf: stage.process(ev))
            }
            events = next
            if events.isEmpty { return }
        }
        for finalEvent in events {
            notifySubscribers(finalEvent)
        }
    }

    private func notifySubscribers(_ event: PipelineEvent) {
        let boxes = lock.withLock { subscriberBoxes }
        for box in boxes {
            box.call(event)
        }
    }
}

// MARK: - Helpers

private final class HandlerBox: @unchecked Sendable {
    let call: (PipelineEvent) -> Void
    init(_ handler: @escaping (PipelineEvent) -> Void) {
        call = handler
    }
}
