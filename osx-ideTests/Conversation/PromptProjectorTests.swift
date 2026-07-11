import XCTest
@testable import osx_ide
import Foundation

final class PromptProjectorTests: XCTestCase {

    private let projector = PromptProjector()
    private let context = ProjectionContext(
        systemPrompt: "You are a helpful assistant.",
        toolDefinitions: "read_file: read a file",
        markCacheBreakpoint: true
    )

    // MARK: - Protected context

    func test_firstMessageIsSystemWithPromptAndTools() async {
        let result = await projector.project([], context: context)
        XCTAssertGreaterThanOrEqual(result.count, 1)
        XCTAssertEqual(result.first?.role, .system)
        XCTAssertTrue(result.first?.content.contains("You are a helpful assistant") == true)
        XCTAssertTrue(result.first?.content.contains("Tool Definitions") == true)
    }

    func test_toolDefinitionsOptional() async {
        let ctx = ProjectionContext(systemPrompt: "Hi", toolDefinitions: "")
        let result = await projector.project([], context: ctx)
        XCTAssertEqual(result.first?.role, .system)
        XCTAssertEqual(result.first?.content, "Hi")
    }

    // MARK: - Turn mapping

    func test_userTextProjectsToUserRole() async {
        let turn = makeTurn(.userText("hello"))
        let result = await projector.project([turn], context: context)
        let userMsg = result.first { $0.role == .user }
        XCTAssertNotNil(userMsg)
        XCTAssertEqual(userMsg?.content, "hello")
    }

    func test_assistantTurnIncludesTextAndReasoning() async {
        let turn = makeTurn(.assistant(text: "answer", reasoning: "thinking", toolCalls: []))
        let result = await projector.project([turn], context: context)
        let assistantMsg = result.first { $0.role == .assistant }
        XCTAssertNotNil(assistantMsg)
        XCTAssertTrue(assistantMsg?.content.contains("thinking") == true)
        XCTAssertTrue(assistantMsg?.content.contains("answer") == true)
    }

    func test_toolResultProjectsToToolRole() async {
        let summary = ToolResultSummary(toolCallId: "tc1", name: "read_file", status: "completed", targetFile: "file.txt", outputRef: nil)
        let turn = makeTurn(.toolResult(summary))
        let result = await projector.project([turn], context: context)
        let toolMsg = result.first { $0.role == .tool }
        XCTAssertNotNil(toolMsg, "Tool result must project to .tool role (leak prevention)")
        XCTAssertTrue(toolMsg?.content.contains("read_file") == true)
        XCTAssertTrue(toolMsg?.content.contains("completed") == true)
    }

    func test_toolResultDoesNotLeakToAssistantRole() async {
        let summary = ToolResultSummary(toolCallId: "tc1", name: "read", status: "completed", targetFile: nil, outputRef: nil)
        let turn = makeTurn(.toolResult(summary))
        let result = await projector.project([turn], context: context)
        let assistantMsgs = result.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMsgs.count, 0, "Tool output must NEVER appear as assistant content (the old leak)")
    }

    func test_checkpointProjectsToSystem() async {
        let turn = makeTurn(.checkpoint("summary text"))
        let result = await projector.project([turn], context: context)
        let sysMsg = result.first { $0.role == .system && $0.content.contains("summary text") }
        XCTAssertNotNil(sysMsg)
    }

    func test_planProjectsToSystem() async {
        let turn = makeTurn(.plan("## plan"))
        let result = await projector.project([turn], context: context)
        let sysMsg = result.first { $0.role == .system && $0.content.contains("plan") }
        XCTAssertNotNil(sysMsg)
    }

    func test_systemTextProjectsToSystem() async {
        let turn = makeTurn(.systemText("important"))
        let result = await projector.project([turn], context: context)
        let sysMsg = result.first { $0.role == .system && $0.content.contains("important") }
        XCTAssertNotNil(sysMsg)
    }

    // MARK: - Cache breakpoint

    func test_cacheBreakpointOnFirstUserMessage() async {
        let turns = [
            makeTurn(.userText("hello")),
            makeTurn(.assistant(text: "hi", reasoning: nil, toolCalls: [])),
            makeTurn(.userText("again")),
        ]
        let result = await projector.project(turns, context: context)
        let breakpointMsgs = result.filter { $0.cacheBreakpointAfter }
        XCTAssertEqual(breakpointMsgs.count, 1, "Only one cache breakpoint")
        XCTAssertEqual(breakpointMsgs.first?.role, .user, "Breakpoint on first user message")
        XCTAssertEqual(breakpointMsgs.first?.content, "hello")
    }

    func test_noCacheBreakpointWhenDisabled() async {
        let ctx = ProjectionContext(systemPrompt: "x", toolDefinitions: "", markCacheBreakpoint: false)
        let turn = makeTurn(.userText("hello"))
        let result = await projector.project([turn], context: ctx)
        let breakpointMsgs = result.filter { $0.cacheBreakpointAfter }
        XCTAssertTrue(breakpointMsgs.isEmpty)
    }

    // MARK: - Stable prefix (determinism)

    func test_deterministicProjection() async {
        let turns = [makeTurn(.userText("a")), makeTurn(.assistant(text: "b", reasoning: nil, toolCalls: []))]
        let r1 = await projector.project(turns, context: context)
        let r2 = await projector.project(turns, context: context)
        XCTAssertEqual(r1.count, r2.count)
        for (m1, m2) in zip(r1, r2) {
            XCTAssertEqual(m1.role, m2.role)
            XCTAssertEqual(m1.content, m2.content)
            XCTAssertEqual(m1.cacheBreakpointAfter, m2.cacheBreakpointAfter)
        }
    }

    func test_stablePrefixTurns0toN() async {
        // prefix [turn0, turn1] must be identical whether alone or with turn2
        let prefixTurns = [
            makeTurn(.userText("first")),
            makeTurn(.assistant(text: "second", reasoning: nil, toolCalls: [])),
        ]
        let fullTurns = prefixTurns + [makeTurn(.userText("third"))]

        let prefixResult = await projector.project(prefixTurns, context: context)
        let fullResult = await projector.project(fullTurns, context: context)

        // The first N projected messages must be identical
        for i in 0..<prefixResult.count {
            guard i < fullResult.count else { XCTFail("prefix longer than full"); return }
            XCTAssertEqual(prefixResult[i].role, fullResult[i].role, "role mismatch at \(i)")
            XCTAssertEqual(prefixResult[i].content, fullResult[i].content, "content mismatch at \(i)")
            XCTAssertEqual(prefixResult[i].cacheBreakpointAfter, fullResult[i].cacheBreakpointAfter, "cache mismatch at \(i)")
        }
    }

    // MARK: - Helpers

    private func makeTurn(_ content: TurnContent) -> Turn {
        Turn(
            meta: TurnMeta(id: UUID(), seq: 0, ts: Date(), producer: .user, sessionId: "t", conversationId: "t"),
            content: content
        )
    }
}
