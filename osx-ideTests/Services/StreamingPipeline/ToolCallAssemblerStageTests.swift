import XCTest
@testable import osx_ide

final class ToolCallAssemblerStageTests: XCTestCase {

    func testPassesOpenedEventThrough() {
        let stage = ToolCallAssemblerStage()
        let event = PipelineEvent.toolCallOpened(id: "c1", tool: "read_file")
        let output = stage.process(event)
        XCTAssertEqual(output.count, 1)
    }

    func testAccumulatesArgumentFragments() {
        let stage = ToolCallAssemblerStage()
        _ = stage.process(PipelineEvent.toolCallOpened(id: "c1", tool: "read_file"))
        _ = stage.process(PipelineEvent.toolCallArguments(id: "c1", fragment: "{\"path\":"))
        _ = stage.process(PipelineEvent.toolCallArguments(id: "c1", fragment: "\"/foo\"}"))
        let flushed = stage.flush()
        let completed = flushed.compactMap { ev -> PipelineEvent? in
            if case .toolCallCompleted = ev { return ev }; return nil
        }
        XCTAssertEqual(completed.count, 1)
        if case .toolCallCompleted(let id, let tool, let args) = completed[0] {
            XCTAssertEqual(id, "c1")
            XCTAssertEqual(tool, "read_file")
            XCTAssertEqual(args["path"] as? String, "/foo")
        }
    }

    func testEmptyArgumentsBecomeEmptyDict() {
        let stage = ToolCallAssemblerStage()
        _ = stage.process(PipelineEvent.toolCallOpened(id: "c1", tool: "read_file"))
        _ = stage.process(PipelineEvent.toolCallArguments(id: "c1", fragment: "{}"))
        let flushed = stage.flush()
        let completed = flushed.compactMap { ev -> PipelineEvent? in
            if case .toolCallCompleted = ev { return ev }; return nil
        }
        XCTAssertEqual(completed.count, 1)
        if case .toolCallCompleted(_, _, let args) = completed[0] {
            XCTAssertTrue(args.isEmpty)
        }
    }

    func testInvalidJSONBecomesFailed() {
        let stage = ToolCallAssemblerStage()
        _ = stage.process(PipelineEvent.toolCallOpened(id: "c1", tool: "read_file"))
        _ = stage.process(PipelineEvent.toolCallArguments(id: "c1", fragment: "{invalid json}"))
        let flushed = stage.flush()
        let failed = flushed.compactMap { ev -> PipelineEvent? in
            if case .toolCallFailed = ev { return ev }; return nil
        }
        XCTAssertEqual(failed.count, 1)
    }

    func testAlreadyFinalizedEventsPassThrough() {
        let stage = ToolCallAssemblerStage()
        let ev = PipelineEvent.toolCallCompleted(id: "c1", tool: "read_file", arguments: ["path": "/f"])
        let output = stage.process(ev)
        XCTAssertEqual(output.count, 1)
    }

    func testMultipleToolCallsAccumulateIndependently() {
        let stage = ToolCallAssemblerStage()
        _ = stage.process(PipelineEvent.toolCallOpened(id: "c1", tool: "read_file"))
        _ = stage.process(PipelineEvent.toolCallOpened(id: "c2", tool: "list_files"))
        _ = stage.process(PipelineEvent.toolCallArguments(id: "c1", fragment: "{\"path\":\"/a\"}"))
        _ = stage.process(PipelineEvent.toolCallArguments(id: "c2", fragment: "{\"path\":\"/b\"}"))
        let flushed = stage.flush()
        XCTAssertEqual(flushed.count, 2)
    }

    func testNonToolEventsPassThrough() {
        let stage = ToolCallAssemblerStage()
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: "hello", source: "t"))
        let output = stage.process(event)
        XCTAssertEqual(output.count, 1)
        guard case .segment = output[0] else { XCTFail(); return }
    }
}
