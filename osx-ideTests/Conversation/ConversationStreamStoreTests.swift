import XCTest
@testable import osx_ide
import Foundation

final class ConversationStreamStoreTests: XCTestCase {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("convlog-\(UUID().uuidString).ndjson")
    }

    func test_appendAssignsMonotonicSeqAndTs() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ConversationStreamStore(fileURL: url)

        let a = try await store.append(
            TurnEvent(producer: .user, sessionId: "s", conversationId: "c", content: .userText("hi"))
        )
        let b = try await store.append(
            TurnEvent(producer: .agent, sessionId: "s", conversationId: "c",
                      content: .assistant(text: "ok", reasoning: nil, toolCalls: []))
        )

        XCTAssertEqual(a.meta.seq, 0)
        XCTAssertEqual(b.meta.seq, a.meta.seq + 1)
        XCTAssertGreaterThanOrEqual(b.meta.ts, a.meta.ts)
    }

    func test_appendOnlyPreservesAllTurnsInOrder() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ConversationStreamStore(fileURL: url)

        for i in 0..<5 {
            _ = try await store.append(
                TurnEvent(producer: .tool, sessionId: "s", conversationId: "c",
                          content: .toolResult(ToolResultSummary(toolCallId: "\(i)", name: "read", status: "completed")))
            )
        }

        let all = await store.allTurns()
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.map(\.meta.seq), Array(0..<5))
    }

    func test_turnsAfterFiltersBySeq() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ConversationStreamStore(fileURL: url)
        for _ in 0..<5 {
            _ = try await store.append(
                TurnEvent(producer: .user, sessionId: "s", conversationId: "c", content: .userText("x"))
            )
        }
        let later = await store.turns(after: 1)
        XCTAssertEqual(later.count, 3)
        XCTAssertEqual(later.first?.meta.seq, 2)
    }

    func test_durabilityAcrossReopen() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ConversationStreamStore(fileURL: url)
        _ = try await store.append(
            TurnEvent(producer: .user, sessionId: "s", conversationId: "c", content: .userText("first"))
        )
        _ = try await store.append(
            TurnEvent(producer: .agent, sessionId: "s", conversationId: "c",
                      content: .assistant(text: "second", reasoning: "r", toolCalls: []))
        )

        let reopened = try ConversationStreamStore(fileURL: url)
        let all = await reopened.allTurns()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.content, .userText("first"))
        XCTAssertEqual(all.last?.content, .assistant(text: "second", reasoning: "r", toolCalls: []))
    }

    func test_noOverwriteOnAppendAfterReload() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ConversationStreamStore(fileURL: url)
        _ = try await store.append(
            TurnEvent(producer: .user, sessionId: "s", conversationId: "c", content: .userText("a"))
        )

        let reopened = try ConversationStreamStore(fileURL: url)
        _ = try await reopened.append(
            TurnEvent(producer: .user, sessionId: "s", conversationId: "c", content: .userText("b"))
        )

        let again = try ConversationStreamStore(fileURL: url)
        let all = await again.allTurns()
        XCTAssertEqual(all.count, 2)
        let texts = all.map { turn -> String in
            if case .userText(let t) = turn.content { return t }
            return ""
        }
        XCTAssertEqual(texts, ["a", "b"])
    }

    func test_latestCheckpointReturnsMostRecent() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ConversationStreamStore(fileURL: url)
        _ = try await store.append(
            TurnEvent(producer: .user, sessionId: "s", conversationId: "c", content: .userText("a"))
        )
        _ = try await store.append(
            TurnEvent(producer: .agent, sessionId: "s", conversationId: "c", content: .checkpoint("summary-1"))
        )
        _ = try await store.append(
            TurnEvent(producer: .user, sessionId: "s", conversationId: "c", content: .userText("b"))
        )

        let cp = await store.latestCheckpoint()
        XCTAssertNotNil(cp)
        if case .checkpoint(let s) = cp?.content {
            XCTAssertEqual(s, "summary-1")
        } else {
            XCTFail("expected a checkpoint turn")
        }
    }
}
