import XCTest

@testable import osx_ide

final class MessageTruncationPolicyTests: XCTestCase {

    // MARK: - Tool Result Truncation

    func testShortToolResultIsNotTruncated() {
        let messages = [
            ChatMessage(role: .tool, content: "short result",
                        tool: ChatMessageToolContext(toolName: "read_file"))
        ]
        let result = MessageTruncationPolicy.truncateForModel(messages)
        XCTAssertEqual(result[0].content, "short result")
    }

    func testLongToolResultIsTruncated() {
        let longContent = String(repeating: "x", count: 6000)
        let messages = [
            ChatMessage(role: .tool, content: longContent,
                        tool: ChatMessageToolContext(toolName: "read_file"))
        ]
        let result = MessageTruncationPolicy.truncateForModel(messages)
        XCTAssertLessThanOrEqual(result[0].content.count,
                                  MessageTruncationPolicy.maxToolResultCharacters + 20)
        XCTAssertTrue(result[0].content.hasSuffix("[truncated]"))
    }

    func testUserMessageIsNeverTruncated() {
        let longContent = String(repeating: "y", count: 5000)
        let messages = [
            ChatMessage(role: .user, content: longContent)
        ]
        let result = MessageTruncationPolicy.truncateForModel(messages)
        XCTAssertEqual(result[0].content.count, 5000)
    }

    func testAssistantMessageIsNeverTruncated() {
        let longContent = String(repeating: "z", count: 5000)
        let messages = [
            ChatMessage(role: .assistant, content: longContent)
        ]
        let result = MessageTruncationPolicy.truncateForModel(messages)
        XCTAssertEqual(result[0].content.count, 5000)
    }

    func testToolNameIsPreservedAfterTruncation() {
        let longContent = String(repeating: "a", count: 5000)
        let messages = [
            ChatMessage(role: .tool, content: longContent,
                        tool: ChatMessageToolContext(toolName: "write_file"))
        ]
        let result = MessageTruncationPolicy.truncateForModel(messages)
        XCTAssertEqual(result[0].toolName, "write_file")
    }

    // MARK: - Character Budget Enforcement

    func testCharacterBudgetEnforcesAggressiveTruncation() {
        let toolContent = String(repeating: "b", count: 4000)
        let messages = [
            ChatMessage(role: .user, content: "do something"),
            ChatMessage(role: .tool, content: toolContent,
                        tool: ChatMessageToolContext(toolName: "t1")),
            ChatMessage(role: .tool, content: toolContent,
                        tool: ChatMessageToolContext(toolName: "t2")),
            ChatMessage(role: .tool, content: toolContent,
                        tool: ChatMessageToolContext(toolName: "t3")),
            ChatMessage(role: .tool, content: toolContent,
                        tool: ChatMessageToolContext(toolName: "t4")),
        ]
        let result = MessageTruncationPolicy.truncateForModel(messages)
        let totalChars = result.reduce(0) { $0 + $1.content.count }
        XCTAssertLessThan(totalChars, MessageTruncationPolicy.maxTotalMessageCharacters,
                          "Total characters should be reduced by budget enforcement")
    }

    // MARK: - Mixed Messages

    func testMixedMessagesOnlyTruncatesToolResults() {
        let longToolContent = String(repeating: "c", count: 6000) // Increased to exceed maxToolResultCharacters
        let messages = [
            ChatMessage(role: .system, content: "You are an assistant"),
            ChatMessage(role: .user, content: "Create a file"),
            ChatMessage(role: .assistant, content: "I'll create that file"),
            ChatMessage(role: .tool, content: longToolContent,
                        tool: ChatMessageToolContext(toolName: "write_file")),
        ]
        let result = MessageTruncationPolicy.truncateForModel(messages)
        XCTAssertEqual(result[0].content, "You are an assistant")
        XCTAssertEqual(result[1].content, "Create a file")
        XCTAssertEqual(result[2].content, "I'll create that file")
        // Find the tool message and check it's truncated
        let toolMessage = result.first { $0.role == .tool }
        XCTAssertNotNil(toolMessage, "Should have a tool message")
        XCTAssertTrue(toolMessage!.content.hasSuffix("\n... [truncated]"))
    }

    func testEmptyMessagesArrayReturnsEmpty() {
        let result = MessageTruncationPolicy.truncateForModel([])
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - ToolOutputArchive (Context Access Layer L0/L1)

final class ToolOutputArchiveTests: XCTestCase {

    func testLargeWindowSlidingModelGetsGenerousLimit() {
        // claude-sonnet-4 is registered as slidingWindow / 200k → limit = 200k * 4.
        let limit = ToolOutputArchive.effectiveToolOutputLimit(modelID: "anthropic/claude-sonnet-4")
        XCTAssertEqual(limit, 200_000 * 4)
    }

    func testSmallWindowCompactionModelFlooredAtMinimum() {
        // deepseek is compaction / 64k → max(12000, 64000/8) = 12000.
        let limit = ToolOutputArchive.effectiveToolOutputLimit(modelID: "deepseek/deepseek")
        XCTAssertEqual(limit, 12_000)
    }

    func testUnknownModelFlooredAtMinimum() {
        let limit = ToolOutputArchive.effectiveToolOutputLimit(modelID: "some-unknown-model")
        XCTAssertEqual(limit, 12_000)
    }

    func testOffloadWritesFileUnderProjectRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolOutputArchiveTests-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let path = ToolOutputArchive.offload(toolCallId: "tc-123", full: "hello world", projectRoot: root)
        let url = URL(fileURLWithPath: path)
        XCTAssertTrue(path.contains("tc-123"))
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(saved, "hello world")
    }

    func testOffloadFallsBackToTempWithoutProjectRoot() {
        let path = ToolOutputArchive.offload(toolCallId: "tc-456", full: "x", projectRoot: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}

// MARK: - LogSummarizer Tests (Context Access Layer L4)

final class LogSummarizerTests: XCTestCase {

    func testDetectsTypeScriptErrors() {
        let log = """
        src/services/UserService.ts:42:5 - error TS2322: Type 'string' is not assignable to type 'number'.
        src/hooks/useUsers.ts:18:12 - error TS18046: 'user' is of type 'unknown'.
        """
        let result = LogSummarizer.summarize(log)
        XCTAssertTrue(result.isLogOutput)
        XCTAssertEqual(result.errorCount, 2)
        XCTAssertTrue(result.brief.contains("errors (2 total)"))
    }

    func testDetectsSwiftErrors() {
        let log = """
        src/models/User.swift:15:8: error: cannot find 'Codable' in scope
        src/views/DetailView.swift:42:12: warning: 'init()' is deprecated
        """
        let result = LogSummarizer.summarize(log)
        XCTAssertTrue(result.isLogOutput)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.warningCount, 1)
    }

    func testDetectsJestFailures() {
        let log = """
        FAIL src/components/UserManagement.test.ts
          ● UserManagement › renders user list
            expect(received).toBe(expected)
            Expected: 3
            Received: 0
        """
        let result = LogSummarizer.summarize(log)
        XCTAssertTrue(result.isLogOutput)
        XCTAssertEqual(result.errorCount, 1)
    }

    func testPlainTextNotDetectedAsLog() {
        let text = "The quick brown fox jumps over the lazy dog."
        let result = LogSummarizer.summarize(text)
        XCTAssertFalse(result.isLogOutput)
        XCTAssertEqual(result.errorCount, 0)
    }

    func testEmptyText() {
        let result = LogSummarizer.summarize("")
        XCTAssertFalse(result.isLogOutput)
        XCTAssertEqual(result.errorCount, 0)
    }
}

// MARK: - ReferenceGraph / PageRank Tests (Context Access Layer L5a)

final class PageRankTests: XCTestCase {

    func testSingleNodeRank() {
        var graph = ReferenceGraph()
        let a = ReferenceGraph.Node(symbolName: "A", filePath: "/a.swift", kind: "class")
        graph.addNode(a)
        let ranks = graph.pageRank(iterations: 10)
        XCTAssertEqual(ranks.count, 1)
        XCTAssertEqual(ranks[a], 1.0)
    }

    func testTwoNodesReferenceEachOther() {
        var graph = ReferenceGraph()
        let a = ReferenceGraph.Node(symbolName: "A", filePath: "/a.swift", kind: "class")
        let b = ReferenceGraph.Node(symbolName: "B", filePath: "/b.swift", kind: "struct")
        graph.addEdge(from: a, to: b)
        graph.addEdge(from: b, to: a)
        let ranks = graph.pageRank(iterations: 20)
        XCTAssertEqual(ranks.count, 2)
        // Both should have roughly equal rank
        XCTAssertGreaterThan(ranks[a]!, 0.3)
        XCTAssertGreaterThan(ranks[b]!, 0.3)
        // Ranks should sum to ~1.0
        let sum = ranks.values.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.01)
    }

    func testHubNodeGetsHigherRank() {
        var graph = ReferenceGraph()
        let hub = ReferenceGraph.Node(symbolName: "Hub", filePath: "/hub.swift", kind: "class")
        let leaf1 = ReferenceGraph.Node(symbolName: "Leaf1", filePath: "/l1.swift", kind: "struct")
        let leaf2 = ReferenceGraph.Node(symbolName: "Leaf2", filePath: "/l2.swift", kind: "enum")
        // leaf1 and leaf2 reference hub, but hub doesn't reference them back
        graph.addEdge(from: leaf1, to: hub)
        graph.addEdge(from: leaf2, to: hub)
        let ranks = graph.pageRank(iterations: 20)
        // Hub should rank higher because it has more incoming edges
        XCTAssertGreaterThan(ranks[hub]!, ranks[leaf1]!)
        XCTAssertGreaterThan(ranks[hub]!, ranks[leaf2]!)
    }
}

// MARK: - Read Dedup Tests (Context Access Layer L5b)

final class ReadDedupTests: XCTestCase {

    func testNonReadMessageNotDeduplicated() {
        let msg = ChatMessage(role: .tool, content: "some content", tool: ChatMessageToolContext(toolName: "write"))
        let result = ReadDedupEngine.deduplicate([msg])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].content, "some content")
    }

    func testShortReadMessageNotDeduplicated() {
        let content = String(repeating: "x", count: 100)
        let msg = ChatMessage(role: .tool, content: content, tool: ChatMessageToolContext(toolName: "read"))
        let result = ReadDedupEngine.deduplicate([msg, msg])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].content, content)
        XCTAssertEqual(result[1].content, content)
    }

    func testDuplicateReadIsReplacedWithPointer() {
        let content = String(repeating: "abcdefghij", count: 100)
        let original = ChatMessage(
            id: UUID(),
            role: .tool,
            content: content,
            timestamp: Date(),
            tool: ChatMessageToolContext(toolName: "read", toolStatus: .completed,
                                          target: ToolInvocationTarget(targetFile: "src/service.ts", toolCallId: "call-1"))
        )
        let duplicate = ChatMessage(
            id: UUID(),
            role: .tool,
            content: content,
            timestamp: Date(),
            tool: ChatMessageToolContext(toolName: "read", toolStatus: .completed,
                                          target: ToolInvocationTarget(targetFile: "src/service.ts", toolCallId: "call-2"))
        )
        let result = ReadDedupEngine.deduplicate([original, duplicate])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].content, content, "First read should be kept as-is")
        XCTAssertTrue(result[1].content.hasPrefix("[read result for"), "Duplicate should be replaced with pointer")
        XCTAssertTrue(result[1].content.contains("message 1"), "Pointer should reference first occurrence index")
    }

    func testDifferentReadsNotDeduplicated() {
        let content1 = String(repeating: "AAAA", count: 200)
        let content2 = String(repeating: "BBBB", count: 200)
        let msg1 = ChatMessage(role: .tool, content: content1, tool: ChatMessageToolContext(toolName: "read"))
        let msg2 = ChatMessage(role: .tool, content: content2, tool: ChatMessageToolContext(toolName: "read"))
        let result = ReadDedupEngine.deduplicate([msg1, msg2])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].content, content1)
        XCTAssertEqual(result[1].content, content2)
    }
}
