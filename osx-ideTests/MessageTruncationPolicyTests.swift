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
        let longContent = String(repeating: "x", count: 5000)
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
        XCTAssertLessThan(totalChars, 16_000,
                          "Total characters should be reduced by budget enforcement")
    }

    // MARK: - Mixed Messages

    func testMixedMessagesOnlyTruncatesToolResults() {
        let longToolContent = String(repeating: "c", count: 5000)
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
        XCTAssertTrue(result[3].content.hasSuffix("[truncated]"))
    }

    func testEmptyMessagesArrayReturnsEmpty() {
        let result = MessageTruncationPolicy.truncateForModel([])
        XCTAssertTrue(result.isEmpty)
    }
}
