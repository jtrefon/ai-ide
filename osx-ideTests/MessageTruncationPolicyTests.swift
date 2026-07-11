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
