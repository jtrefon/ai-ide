import XCTest
@testable import osx_ide
import Foundation

final class ConversationCoordinatorTests: XCTestCase {


    // MARK: - Session lifecycle

    func test_startAndSwitchSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "a",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        let id1 = await coord.currentSessionId
        XCTAssertEqual(id1, "a")

        await coord.startSession("b")
        let id2 = await coord.currentSessionId
        XCTAssertEqual(id2, "b")

        await coord.switchSession(to: "a")
        let id3 = await coord.currentSessionId
        XCTAssertEqual(id3, "a")

        await coord.closeSession("b")
        let id4 = await coord.currentSessionId
        XCTAssertEqual(id4, "a")
    }

    // MARK: - Turn submission

    func test_submitUserMessageAppendsTurn() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s1",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.submitUserMessage("hello", sessionId: "s1")
        let turns = await coord.allTurns(sessionId: "s1")
        XCTAssertEqual(turns.count, 1)
        if case .userText(let t) = turns.first?.content {
            XCTAssertEqual(t, "hello")
        } else {
            XCTFail("expected userText turn")
        }
    }

    func test_commitAgentTurnAppendsCorrectly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s1",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.commitAgentTurn(
            text: "response",
            reasoning: "none",
            toolCalls: [ToolCallSummary(toolCallId: "tc1", name: "read", argumentsDigest: "abc")],
            sessionId: "s1"
        )
        let turns = await coord.allTurns(sessionId: "s1")
        XCTAssertEqual(turns.count, 1)
        if case .assistant(let text, let reasoning, let calls) = turns.first?.content {
            XCTAssertEqual(text, "response")
            XCTAssertEqual(reasoning, "none")
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.toolCallId, "tc1")
        } else {
            XCTFail("expected assistant turn")
        }
    }

    func test_commitToolResultAppendsTurn() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s1",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.commitToolResult(
            toolCallId: "tc1",
            name: "read_file",
            status: "completed",
            targetFile: "file.txt",
            outputRef: "ref123",
            sessionId: "s1"
        )
        let turns = await coord.allTurns(sessionId: "s1")
        XCTAssertEqual(turns.count, 1)
        if case .toolResult(let r) = turns.first?.content {
            XCTAssertEqual(r.toolCallId, "tc1")
            XCTAssertEqual(r.name, "read_file")
            XCTAssertEqual(r.status, "completed")
            XCTAssertEqual(r.targetFile, "file.txt")
            XCTAssertEqual(r.outputRef, "ref123")
        } else {
            XCTFail("expected toolResult turn")
        }
    }

    func test_sessionIsolationDifferentSessions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s1",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.submitUserMessage("from-s1", sessionId: "s1")
        await coord.startSession("s2")
        try await coord.submitUserMessage("from-s2", sessionId: "s2")

        let s1Turns = await coord.allTurns(sessionId: "s1")
        let s2Turns = await coord.allTurns(sessionId: "s2")
        XCTAssertEqual(s1Turns.count, 1)
        XCTAssertEqual(s2Turns.count, 1)
        if case .userText(let t1) = s1Turns.first?.content { XCTAssertEqual(t1, "from-s1") }
        if case .userText(let t2) = s2Turns.first?.content { XCTAssertEqual(t2, "from-s2") }
    }

    // MARK: - Compaction

    func test_compactAppendsCheckpoint() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s1",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.submitUserMessage("a", sessionId: "s1")
        try await coord.commitAgentTurn(text: "b", reasoning: nil, toolCalls: [], sessionId: "s1")

        try await coord.compact(sessionId: "s1")

        let turns = await coord.allTurns(sessionId: "s1")
        XCTAssertEqual(turns.count, 3)  // 2 turns + checkpoint
        if case .checkpoint(let summary) = turns.last?.content {
            XCTAssertTrue(summary.contains("checkpoint"))
        } else {
            XCTFail("expected checkpoint turn")
        }
    }

    func test_autoCompactOnThreshold() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Threshold of 3 turns
        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s1",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 3)

        try await coord.submitUserMessage("1", sessionId: "s1")
        try await coord.commitAgentTurn(text: "2", reasoning: nil, toolCalls: [], sessionId: "s1")
        try await coord.commitToolResult(toolCallId: "t1", name: "r", status: "done", targetFile: nil, outputRef: nil, sessionId: "s1")
        // Submitting the 4th turn should trigger the 3-turn threshold
        try await coord.submitUserMessage("4", sessionId: "s1")

        let turns = await coord.allTurns(sessionId: "s1")
        // Expect: 4 turns + 1 checkpoint (triggered on 4th turn)
        XCTAssertEqual(turns.count, 5)
        let hasCheckpoint = turns.contains { if case .checkpoint = $0.content { return true }; return false }
        XCTAssertTrue(hasCheckpoint, "Auto-compaction should have appended a checkpoint")
    }

    // MARK: - Commit helpers

    func test_commitSystemMessage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.commitSystemMessage("sys msg", sessionId: "s")
        let turns = await coord.allTurns(sessionId: "s")
        if case .systemText(let t) = turns.first?.content {
            XCTAssertEqual(t, "sys msg")
        } else { XCTFail("expected systemText") }
    }

    func test_commitPlan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.commitPlan("## plan", sessionId: "s")
        let turns = await coord.allTurns(sessionId: "s")
        if case .plan(let p) = turns.first?.content {
            XCTAssertEqual(p, "## plan")
        } else { XCTFail("expected plan") }
    }

    func test_turnsAfterSeq() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = SessionRegistry(
            projectRoot: root,
            initialSessionId: "s",
            retention: TimeBasedRetention(maxAge: 86400)
        )
        let coord = ConversationCoordinator(registry: registry, compactionThreshold: 100)

        try await coord.submitUserMessage("0", sessionId: "s")
        try await coord.submitUserMessage("1", sessionId: "s")
        try await coord.submitUserMessage("2", sessionId: "s")

        let after = await coord.turns(after: 0, sessionId: "s")
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.first?.meta.seq, 1)
    }
}
