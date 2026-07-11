import XCTest
import Combine
@testable import osx_ide

@MainActor
final class StreamingUIAdapterTests: XCTestCase {

    func testAttachDetachLifecycle() {
        let eventBus = MockEventBus()
        let adapter = StreamingUIAdapter(eventBus: eventBus)
        let pipeline = EventPipeline()

        adapter.attach(to: pipeline, runId: "test-run")
        // No crash = attached successfully

        adapter.detach()
        // No crash = detached successfully
    }

    func testSegmentUserVisiblePublishesChunkEvent() {
        let eventBus = MockEventBus()
        let adapter = StreamingUIAdapter(eventBus: eventBus)
        let pipeline = EventPipeline()
        adapter.attach(to: pipeline, runId: "r1")

        var receivedChunks: [String] = []
        let c = eventBus.subscribe(to: LocalModelStreamingChunkEvent.self) { event in
            receivedChunks.append(event.chunk)
        }
        defer { c.cancel() }

        pipeline.ingest(.segment(Segment(kind: .userVisible, text: "hello", source: "t")))
        pipeline.ingest(.segment(Segment(kind: .userVisible, text: " world", source: "t")))

        XCTAssertEqual(receivedChunks, ["hello", " world"])
    }

    func testSegmentReasoningPublishesReasoningEvent() {
        let eventBus = MockEventBus()
        let adapter = StreamingUIAdapter(eventBus: eventBus)
        let pipeline = EventPipeline()
        adapter.attach(to: pipeline, runId: "r1")

        var receivedReasoning: [String] = []
        let c = eventBus.subscribe(to: LocalModelStreamingReasoningChunkEvent.self) { event in
            receivedReasoning.append(event.chunk)
        }
        defer { c.cancel() }

        pipeline.ingest(.segment(Segment(kind: .reasoning, text: "think step", source: "t")))

        XCTAssertEqual(receivedReasoning, ["think step"])
    }

    func testSegmentToolCallMarkupNotPublished() {
        let eventBus = MockEventBus()
        let adapter = StreamingUIAdapter(eventBus: eventBus)
        let pipeline = EventPipeline()
        adapter.attach(to: pipeline, runId: "r1")

        var chunkCount = 0
        let c1 = eventBus.subscribe(to: LocalModelStreamingChunkEvent.self) { _ in chunkCount += 1 }
        var reasoningCount = 0
        let c2 = eventBus.subscribe(to: LocalModelStreamingReasoningChunkEvent.self) { _ in reasoningCount += 1 }
        defer { c1.cancel(); c2.cancel() }

        pipeline.ingest(.segment(Segment(kind: .toolCallMarkup, text: "<tool_call>", source: "t")))

        XCTAssertEqual(chunkCount, 0)
        XCTAssertEqual(reasoningCount, 0)
    }

    func testSegmentStatusPublishesStatusEvent() {
        let eventBus = MockEventBus()
        let adapter = StreamingUIAdapter(eventBus: eventBus)
        let pipeline = EventPipeline()
        adapter.attach(to: pipeline, runId: "r1")

        var messages: [String] = []
        let c = eventBus.subscribe(to: LocalModelStreamingStatusEvent.self) { event in
            messages.append(event.message)
        }
        defer { c.cancel() }

        pipeline.ingest(.segment(Segment(kind: .status, text: "thinking...", source: "t")))

        XCTAssertEqual(messages, ["thinking..."])
    }

    func testEventsBeforeAttachAreIgnored() {
        let eventBus = MockEventBus()
        let adapter = StreamingUIAdapter(eventBus: eventBus)
        let pipeline = EventPipeline()

        var chunkCount = 0
        let c = eventBus.subscribe(to: LocalModelStreamingChunkEvent.self) { _ in chunkCount += 1 }
        defer { c.cancel() }

        pipeline.ingest(.segment(Segment(kind: .userVisible, text: "before", source: "t")))
        XCTAssertEqual(chunkCount, 0)
    }

    func testEventsAfterDetachAreIgnored() {
        let eventBus = MockEventBus()
        let adapter = StreamingUIAdapter(eventBus: eventBus)
        let pipeline = EventPipeline()
        adapter.attach(to: pipeline, runId: "r1")
        adapter.detach()

        var chunkCount = 0
        let c = eventBus.subscribe(to: LocalModelStreamingChunkEvent.self) { _ in chunkCount += 1 }
        defer { c.cancel() }

        pipeline.ingest(.segment(Segment(kind: .userVisible, text: "after", source: "t")))
        XCTAssertEqual(chunkCount, 0)
    }
}

// MARK: - Mock

private final class MockEventBus: @unchecked Sendable, EventBusProtocol {
    private var lock = NSLock()
    private var handlers: [String: [(Any) -> Void]] = [:]

    func publish<E: Event>(_ event: E) {
        let key = String(describing: E.self)
        lock.withLock {
            for handler in handlers[key] ?? [] {
                handler(event)
            }
        }
    }

    func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
        let key = String(describing: E.self)
        let box: (Any) -> Void = { any in
            guard let e = any as? E else { return }
            handler(e)
        }
        lock.withLock {
            handlers[key, default: []].append(box)
        }
        return AnyCancellable { [weak self] in
            self?.lock.withLock {
                self?.handlers[key]?.removeAll { $0 as AnyObject === box as AnyObject }
            }
        }
    }
}
