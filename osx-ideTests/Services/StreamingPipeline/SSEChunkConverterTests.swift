import XCTest
@testable import osx_ide

final class SSEChunkConverterTests: XCTestCase {

    func testEmptyChunkProducesNoEvents() {
        let json = """
        {"choices":[{"delta":{}}]}
        """
        let chunk = decodeChunk(json)
        let events = SSEChunkConverter.convert(chunk)
        XCTAssertEqual(events.count, 0)
    }

    func testContentChunkProducesSegment() {
        let json = """
        {"choices":[{"delta":{"content":"Hello"}}]}
        """
        let chunk = decodeChunk(json)
        let events = SSEChunkConverter.convert(chunk)
        XCTAssertEqual(events.count, 1)
        guard case .segment(let segment) = events[0] else { XCTFail(); return }
        XCTAssertEqual(segment.kind, .userVisible)
        XCTAssertEqual(segment.text, "Hello")
    }

    func testReasoningChunkProducesReasoningSegment() {
        let json = """
        {"choices":[{"delta":{"reasoning":"thinking..."}}]}
        """
        let chunk = decodeChunk(json)
        let events = SSEChunkConverter.convert(chunk)
        XCTAssertEqual(events.count, 1)
        guard case .segment(let segment) = events[0] else { XCTFail(); return }
        XCTAssertEqual(segment.kind, .reasoning)
    }

    func testFinishReasonEmitsStatusAndFinished() {
        let json = """
        {"choices":[{"delta":{},"finish_reason":"stop"}]}
        """
        let chunk = decodeChunk(json)
        let events = SSEChunkConverter.convert(chunk)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.contains(where: { if case .finished = $0 { return true }; return false }))
    }

    func testUsageEmitsStatus() {
        let json = """
        {"choices":[{"delta":{}}],"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}
        """
        let chunk = decodeChunk(json)
        let events = SSEChunkConverter.convert(chunk)
        XCTAssertTrue(events.contains(where: {
            if case .status(_, let info) = $0, info.code == "usage" { return true }; return false
        }))
    }

    // MARK: - Helpers

    private func decodeChunk(_ json: String) -> OpenRouterChatResponseChunk {
        try! JSONDecoder().decode(OpenRouterChatResponseChunk.self, from: json.data(using: .utf8)!)
    }
}
