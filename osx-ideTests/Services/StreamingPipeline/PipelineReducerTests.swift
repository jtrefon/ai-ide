import XCTest
@testable import osx_ide

final class PipelineReducerTests: XCTestCase {

    func testSegmentUserVisibleAppendsContent() {
        let state = PipelineState()
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: "Hello ", source: "test"))
        let state2 = PipelineReducer.reduce(state: state, event: event)
        XCTAssertEqual(state2.content, "Hello ")
        let state3 = PipelineReducer.reduce(state: state2, event: event)
        XCTAssertEqual(state3.content, "Hello Hello ")
    }

    func testSegmentReasoningAppends() {
        let state = PipelineState()
        let event = PipelineEvent.segment(Segment(kind: .reasoning, text: "step 1", source: "test"))
        let state2 = PipelineReducer.reduce(state: state, event: event)
        XCTAssertEqual(state2.reasoning, "step 1")
        let event3 = PipelineEvent.segment(Segment(kind: .reasoning, text: " step 2", source: "test"))
        let state3 = PipelineReducer.reduce(state: state2, event: event3)
        XCTAssertEqual(state3.reasoning, "step 1 step 2")
    }

    func testSegmentToolCallMarkupIsSuppressed() {
        let state = PipelineState()
        let event = PipelineEvent.segment(Segment(kind: .toolCallMarkup, text: "<tool_call>", source: "test"))
        let state2 = PipelineReducer.reduce(state: state, event: event)
        XCTAssertEqual(state2.content, "")
        XCTAssertNil(state2.reasoning)
    }

    func testToolCallOpenedCreatesDraft() {
        let state = PipelineState()
        let event = PipelineEvent.toolCallOpened(id: "call-1", tool: "read_file")
        let state2 = PipelineReducer.reduce(state: state, event: event)
        XCTAssertNotNil(state2.toolCallDrafts["call-1"])
        XCTAssertEqual(state2.toolCallDrafts["call-1"]?.tool, "read_file")
        XCTAssertEqual(state2.toolCallDrafts["call-1"]?.accumulatedArguments, "")
    }

    func testToolCallArgumentsAppendToBuffer() {
        let state = PipelineState()
        let s1 = PipelineReducer.reduce(state: state, event: .toolCallOpened(id: "c1", tool: "read_file"))
        let s2 = PipelineReducer.reduce(state: s1, event: .toolCallArguments(id: "c1", fragment: "{\"path\":"))
        let s3 = PipelineReducer.reduce(state: s2, event: .toolCallArguments(id: "c1", fragment: "\"/foo\"}"))
        XCTAssertEqual(s3.toolCallDrafts["c1"]?.accumulatedArguments, "{\"path\":\"/foo\"}")
    }

    func testToolCallCompletedRemovesDraftAndRecords() {
        let state = PipelineState()
        let s1 = PipelineReducer.reduce(state: state, event: .toolCallOpened(id: "c1", tool: "read_file"))
        let s2 = PipelineReducer.reduce(state: s1, event: .toolCallCompleted(id: "c1", tool: "read_file", arguments: ["path": "/foo"]))
        XCTAssertNil(s2.toolCallDrafts["c1"])
        XCTAssertEqual(s2.completedToolCalls.count, 1)
        XCTAssertEqual(s2.completedToolCalls[0].id, "c1")
        XCTAssertEqual(s2.completedToolCalls[0].tool, "read_file")
    }

    func testToolCallFailedRemovesDraftAndRecords() {
        let state = PipelineState()
        let s1 = PipelineReducer.reduce(state: state, event: .toolCallOpened(id: "c1", tool: "read_file"))
        let s2 = PipelineReducer.reduce(state: s1, event: .toolCallFailed(id: "c1", tool: "read_file", rawArguments: "{invalid", error: "parse error"))
        XCTAssertNil(s2.toolCallDrafts["c1"])
        XCTAssertEqual(s2.malformedToolCalls.count, 1)
        XCTAssertEqual(s2.malformedToolCalls[0].error, "parse error")
    }

    func testStatusAccumulatesByProvider() {
        let state = PipelineState()
        let s1 = PipelineReducer.reduce(state: state, event: .status(provider: "openrouter", info: PipelineStatusInfo(code: "thinking", detail: "")))
        let s2 = PipelineReducer.reduce(state: s1, event: .status(provider: "openrouter", info: PipelineStatusInfo(code: "done", detail: "")))
        XCTAssertEqual(s2.status["openrouter"]?.code, "done")
    }

    func testFinishedSetsIsComplete() {
        let state = PipelineState()
        let s1 = PipelineReducer.reduce(state: state, event: .finished)
        XCTAssertTrue(s1.isComplete)
    }

    func testErrorSetsIsCompleteAndStoresError() {
        let state = PipelineState()
        let err = PipelineError(code: .parseFailure, message: "oops", sourceStage: "test")
        let s1 = PipelineReducer.reduce(state: state, event: .error(err))
        XCTAssertTrue(s1.isComplete)
        XCTAssertEqual(s1.error?.code, .parseFailure)
        XCTAssertEqual(s1.error?.message, "oops")
    }

    func testSegmentErrorCreatesPipelineError() {
        let state = PipelineState()
        let event = PipelineEvent.segment(Segment(kind: .error, text: "parse error", source: "tokenizer"))
        let s1 = PipelineReducer.reduce(state: state, event: event)
        XCTAssertTrue(s1.isComplete)
        XCTAssertEqual(s1.error?.code, .stageFailure)
        XCTAssertEqual(s1.error?.message, "parse error")
    }

    func testMultipleEventsProduceCorrectAggregateState() {
        let state = PipelineState()
        let events: [PipelineEvent] = [
            .segment(Segment(kind: .userVisible, text: "I'll help.\n", source: "model")),
            .segment(Segment(kind: .reasoning, text: "Need to read file", source: "model")),
            .toolCallOpened(id: "tc1", tool: "read_file"),
            .toolCallArguments(id: "tc1", fragment: "{\"path\":"),
            .toolCallArguments(id: "tc1", fragment: "\"/src/main.js\"}"),
            .toolCallCompleted(id: "tc1", tool: "read_file", arguments: ["path": "/src/main.js"]),
        ]
        let finalState = events.reduce(state) { PipelineReducer.reduce(state: $0, event: $1) }

        XCTAssertTrue(finalState.content.contains("I'll help"))
        XCTAssertEqual(finalState.reasoning, "Need to read file")
        XCTAssertEqual(finalState.completedToolCalls.count, 1)
        XCTAssertEqual(finalState.completedToolCalls[0].tool, "read_file")
        XCTAssertNil(finalState.error)
        XCTAssertFalse(finalState.isComplete)

        let finishedState = PipelineReducer.reduce(state: finalState, event: .finished)
        XCTAssertTrue(finishedState.isComplete)
    }
}
