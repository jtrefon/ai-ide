import XCTest
import Combine
@testable import osx_ide

final class BufferCoordinatorStageTests: XCTestCase {

    func testAccumulatesContentViaReducer() {
        let stage = BufferCoordinatorStage()
        _ = stage.process(PipelineEvent.segment(Segment(kind: .userVisible, text: "Hello ", source: "t")))
        _ = stage.process(PipelineEvent.segment(Segment(kind: .userVisible, text: "world", source: "t")))
        XCTAssertEqual(stage.state.content, "Hello world")
    }

    func testAccumulatesReasoning() {
        let stage = BufferCoordinatorStage()
        _ = stage.process(PipelineEvent.segment(Segment(kind: .reasoning, text: "think step 1", source: "t")))
        XCTAssertEqual(stage.state.reasoning, "think step 1")
    }

    func testAccumulatesToolCalls() {
        let stage = BufferCoordinatorStage()
        _ = stage.process(PipelineEvent.toolCallOpened(id: "c1", tool: "read_file"))
        _ = stage.process(PipelineEvent.toolCallArguments(id: "c1", fragment: "{\"path\":\"/f\"}"))
        _ = stage.process(PipelineEvent.toolCallCompleted(id: "c1", tool: "read_file", arguments: ["path": "/f"]))
        XCTAssertEqual(stage.state.completedToolCalls.count, 1)
        XCTAssertEqual(stage.state.completedToolCalls[0].tool, "read_file")
        XCTAssertTrue(stage.state.toolCallDrafts.isEmpty)
    }

    func testPassesEventsThrough() {
        let stage = BufferCoordinatorStage()
        let events = [PipelineEvent.finished]
        let output = events.flatMap { stage.process($0) }
        XCTAssertEqual(output.count, 1)
        guard case .finished = output[0] else { XCTFail(); return }
    }

    func testFlushEmitsStatus() {
        let stage = BufferCoordinatorStage()
        let events = stage.flush()
        XCTAssertEqual(events.count, 1)
        guard case .status(_, let info) = events[0] else { XCTFail(); return }
        XCTAssertEqual(info.code, "pipeline_complete")
    }

    func testStatePublisherEmitsOnEachEvent() {
        let stage = BufferCoordinatorStage()
        var emissions: [PipelineState] = []
        let cancellable = stage.statePublisher.sink { emissions.append($0) }
        defer { cancellable.cancel() }

        _ = stage.process(PipelineEvent.segment(Segment(kind: .userVisible, text: "a", source: "t")))
        _ = stage.process(PipelineEvent.segment(Segment(kind: .userVisible, text: "b", source: "t")))
        XCTAssertEqual(emissions.count, 2)
        XCTAssertEqual(emissions.last?.content, "ab")
    }

    func testStateAfterFinished() {
        let stage = BufferCoordinatorStage()
        _ = stage.process(PipelineEvent.finished)
        XCTAssertTrue(stage.state.isComplete)
    }

    func testStateAfterToolCallFailed() {
        let stage = BufferCoordinatorStage()
        _ = stage.process(PipelineEvent.toolCallFailed(id: "c1", tool: "read_file", rawArguments: "{bad", error: "parse error"))
        XCTAssertEqual(stage.state.malformedToolCalls.count, 1)
        XCTAssertEqual(stage.state.malformedToolCalls[0].error, "parse error")
    }
}
