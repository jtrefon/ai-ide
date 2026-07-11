import XCTest
@testable import osx_ide

final class ReasoningExtractionStageTests: XCTestCase {

    func testPlainContentPassesThroughUnchanged() {
        let stage = ReasoningExtractionStage()
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: "Hello world", source: "test"))
        let output = stage.process(event)
        XCTAssertEqual(output.count, 1)
        guard case .segment(let seg) = output[0] else { XCTFail(); return }
        XCTAssertEqual(seg.kind, .userVisible)
        XCTAssertEqual(seg.text, "Hello world")
    }

    func testThinkTagExtractsReasoning() {
        let stage = ReasoningExtractionStage()
        let text = "Before<think>deep thoughts</think>After"
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: text, source: "test"))
        let output = stage.process(event)
        XCTAssertEqual(output.count, 3)
        XCTAssertEqual(output.filter { if case .segment(let s) = $0, s.kind == .reasoning { return true }; return false }.count, 1)
        XCTAssertEqual(output.filter { if case .segment(let s) = $0, s.kind == .userVisible { return true }; return false }.count, 2)
    }

    func testThinkingTag() {
        let stage = ReasoningExtractionStage()
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: "<thinking>inner</thinking>after", source: "t"))
        let output = stage.process(event)
        XCTAssertEqual(output.count, 2)
        guard case .segment(let r) = output[0], r.kind == .reasoning else { XCTFail(); return }
        XCTAssertEqual(r.text, "inner")
    }

    func testIdeReasoningTag() {
        let stage = ReasoningExtractionStage()
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: "<ide_reasoning>analysis</ide_reasoning>response", source: "t"))
        let output = stage.process(event)
        XCTAssertEqual(output.count, 2)
    }

    func testAlreadyReasoningSegmentPassesThrough() {
        let stage = ReasoningExtractionStage()
        let event = PipelineEvent.segment(Segment(kind: .reasoning, text: "already extracted", source: "t"))
        let output = stage.process(event)
        XCTAssertEqual(output.count, 1)
    }

    func testNonSegmentEventsPassThrough() {
        let stage = ReasoningExtractionStage()
        let event = PipelineEvent.finished
        let output = stage.process(event)
        XCTAssertEqual(output.count, 1)
        guard case .finished = output[0] else { XCTFail(); return }
    }

    func testNoTagLeavesContentIntact() {
        let stage = ReasoningExtractionStage()
        let events = (0..<3).map { _ in
            PipelineEvent.segment(Segment(kind: .userVisible, text: "line\n", source: "t"))
        }
        let results = events.flatMap { stage.process($0) }
        let combined = results.compactMap { ev -> String? in
            guard case .segment(let s) = ev, s.kind == .userVisible else { return nil }
            return s.text
        }.joined()
        XCTAssertEqual(combined, "line\nline\nline\n")
    }

    func testFlushEmitsPendingContent() {
        let stage = ReasoningExtractionStage()
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: "<think>partial", source: "t"))
        let beforeFlush = stage.process(event)
        // Opening tag without closing → content buffered, no output
        XCTAssertEqual(beforeFlush.count, 0)
        // Finish triggers close-tag detection
        let final = PipelineEvent.segment(Segment(kind: .userVisible, text: "</think>done", source: "t"))
        let afterClose = stage.process(final)
        XCTAssertGreaterThan(afterClose.count, 0)
        // reasoning should be "partial", visible should be "done"
        let reasoning = afterClose.compactMap { ev -> String? in
            guard case .segment(let s) = ev, s.kind == .reasoning else { return nil }
            return s.text
        }.joined()
        XCTAssertEqual(reasoning, "partial")
    }

    func testGemma4Reasoning() {
        let stage = ReasoningExtractionStage()
        let text = "<|channel>thought\nreasoning content<channel|>after content"
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: text, source: "t"))
        let output = stage.process(event)
        XCTAssertGreaterThanOrEqual(output.count, 2)
        let reasoning = output.compactMap { ev -> String? in
            guard case .segment(let s) = ev, s.kind == .reasoning else { return nil }
            return s.text
        }.joined()
        XCTAssertEqual(reasoning, "reasoning content")
    }

    func testLegacyGemmaReasoning() {
        let stage = ReasoningExtractionStage()
        let text = "<|channel|>thought\nold style<|channel|>responsevisible"
        let event = PipelineEvent.segment(Segment(kind: .userVisible, text: text, source: "t"))
        let output = stage.process(event)
        let reasoning = output.compactMap { ev -> String? in
            guard case .segment(let s) = ev, s.kind == .reasoning else { return nil }
            return s.text
        }.joined()
        XCTAssertEqual(reasoning, "old style")
    }
}
