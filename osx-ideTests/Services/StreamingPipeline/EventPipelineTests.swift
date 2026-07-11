import XCTest
import Combine
@testable import osx_ide

final class EventPipelineTests: XCTestCase {

    func testEmptyPipelinePassesThrough() {
        let pipeline = EventPipeline()
        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)
        XCTAssertEqual(received.count, 1)
        if case .finished = received[0] { /* pass */ } else { XCTFail("expected finished") }
    }

    func testSingleStageTransforms() {
        let stage = NullStage()
        let pipeline = EventPipeline(stages: [stage])
        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.segment(Segment(kind: .userVisible, text: "hello", source: "test")))

        // NullStage swallows events, so the subscriber should receive nothing
        XCTAssertEqual(received.count, 0)
    }

    func testTraceStageLogsEvents() {
        var logged: [PipelineEvent] = []
        let trace = TraceStage { logged.append($0) }
        let pipeline = EventPipeline(stages: [trace])

        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)

        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(received.count, 1)
    }

    /// A stage that doubles every incoming event
    private final class DoublingStage: PipelineStage, @unchecked Sendable {
        let identifier = "doubler"
        func process(_ event: PipelineEvent) -> [PipelineEvent] { [event, event] }
        func flush() -> [PipelineEvent] { [] }
    }

    func testStageFanOut() {
        let doubler = DoublingStage()
        let pipeline = EventPipeline(stages: [doubler])

        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)

        XCTAssertEqual(received.count, 2)
    }

    /// A stage that filters out all events
    private final class FilterStage: PipelineStage, @unchecked Sendable {
        let identifier = "filter"
        func process(_ event: PipelineEvent) -> [PipelineEvent] { [] }
        func flush() -> [PipelineEvent] { [] }
    }

    func testStageSwallowsEvents() {
        let filter = FilterStage()
        let pipeline = EventPipeline(stages: [filter])

        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)
        // Filter swallows, so .finished is NOT emitted
        XCTAssertEqual(received.count, 0)
    }

    func testMultipleStagesChain() {
        let doubler1 = DoublingStage()  // 1 event → 2
        let tracker = TraceStage { _ in }
        let doubler2 = DoublingStage()  // 2 events → 4
        let pipeline = EventPipeline(stages: [doubler1, tracker, doubler2])

        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)
        // doubler1: 1→2, tracker passes both, doubler2: 2→4
        XCTAssertEqual(received.count, 4)
    }

    func testInsertStageDynamically() {
        let filter = FilterStage()
        let pipeline = EventPipeline(stages: [filter])
        let trace = TraceStage { _ in }
        pipeline.insert(trace, after: filter)

        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)
        XCTAssertEqual(received.count, 0) // filter swallows before trace
    }

    func testRemoveStage() {
        let filter = FilterStage()
        let pipeline = EventPipeline(stages: [filter])
        pipeline.remove(filter)

        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)
        XCTAssertEqual(received.count, 1) // no filter, so finished passes through
    }

    func testReplaceStage() {
        let filter = FilterStage()
        let pipeline = EventPipeline(stages: [filter])
        pipeline.replace(filter, with: NullStage())

        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest(.finished)
        // NullStage swallows, so finished does NOT pass through
        XCTAssertEqual(received.count, 0)
    }

    func testFinishFlushesStages() {
        let expFlush = expectation(description: "flush called")
        let flushingStage = FlushSpyStage(onFlush: { expFlush.fulfill() })
        let pipeline = EventPipeline(stages: [flushingStage])
        pipeline.finish()
        wait(for: [expFlush], timeout: 1)
    }

    func testMultipleIngest() {
        let pipeline = EventPipeline()
        var received: [PipelineEvent] = []
        let cancellable = pipeline.observe { received.append($0) }
        defer { cancellable.cancel() }

        pipeline.ingest([
            .segment(Segment(kind: .userVisible, text: "a", source: "t")),
            .segment(Segment(kind: .userVisible, text: "b", source: "t")),
            .finished,
        ])
        XCTAssertEqual(received.count, 3)
    }

    func testObservationCancellableRemovesSubscriber() {
        let pipeline = EventPipeline()
        var received: [PipelineEvent] = []
        var cancellable: AnyCancellable? = pipeline.observe { received.append($0) }

        pipeline.ingest(.finished)
        XCTAssertEqual(received.count, 1)

        cancellable?.cancel()
        cancellable = nil

        pipeline.ingest(.finished)
        XCTAssertEqual(received.count, 1) // no longer observing
    }
}

// MARK: - Helper

private final class FlushSpyStage: PipelineStage, @unchecked Sendable {
    let identifier = "flush_spy"
    let onFlush: () -> Void
    init(onFlush: @escaping () -> Void) { self.onFlush = onFlush }
    func process(_ event: PipelineEvent) -> [PipelineEvent] { [event] }
    func flush() -> [PipelineEvent] { onFlush(); return [] }
}
