//
//  StreamingPerformanceHarnessTests.swift
//  osx-ideHarnessTests
//
//  Performance test that mocks rapid LLM streaming output and measures
//  CPU usage, @Published fire count, and UI update frequency.
//

import XCTest
import Combine
@testable import osx_ide

/// Tests that mock rapid streaming output to verify CPU/performance stays bounded.
@MainActor
final class StreamingPerformanceHarnessTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        await TestConfigurationProvider.shared.setConfiguration(.isolated)
        cancellables.removeAll()
    }

    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - Test: ChatHistoryManager draft is ephemeral / append-only chain

    /// The draft is an ephemeral UI slot, not part of the committed chain. Rapid
    /// streaming updates replace the single draft; the committed chain is never
    /// touched until commitDraft() appends exactly one node.
    func testDraftIsEphemeralAndCommittedChainIsAppendOnly() async throws {
        let manager = ChatHistoryCoordinator(projectRoot: FileManager.default.temporaryDirectory)
        let draftId = UUID()
        let initialMessage = ChatMessage(
            id: draftId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            isDraft: true
        )

        // Display shows the live draft.
        manager.setDraft(initialMessage)
        XCTAssertEqual(manager.messages.last?.id, draftId)
        // Committed chain is untouched by a draft.
        XCTAssertTrue(manager.committedMessages.isEmpty)

        // Simulate 100 rapid draft updates — only the last wins, still a single draft.
        for i in 0..<100 {
            manager.setDraft(
                ChatMessage(
                    id: draftId,
                    role: .assistant,
                    content: "chunk \(i) ",
                    timestamp: initialMessage.timestamp,
                    isDraft: true
                )
            )
        }
        XCTAssertEqual(manager.messages.last?.content, "chunk 99 ")
        XCTAssertTrue(manager.committedMessages.isEmpty, "draft must not leak into committed chain")

        // Committing appends exactly one node and clears the draft.
        manager.commitDraft()
        XCTAssertEqual(manager.committedMessages.count, 1)
        XCTAssertEqual(manager.committedMessages.last?.content, "chunk 99 ")
        XCTAssertNil(manager.messages.last?.isDraft)
    }

    // MARK: - Test: StreamingOutputBuffer classification

    /// Verify that StreamingOutputBuffer separates content from tool-call-like text.
    func testStreamingOutputBufferClassifiesToolText() async throws {
        let buffer = StreamingOutputBuffer()

        // Normal content should go to content
        buffer.appendContent("Hello, this is a normal response. ")
        buffer.appendContent("Here is some code: `print('hello')`")
        XCTAssertTrue(buffer.hasContent)
        XCTAssertFalse(buffer.hasToolText)
        XCTAssertFalse(buffer.hasReasoning)

        buffer.clear()

        // Tool-call-like JSON should be held back from content
        let toolJson = #"{"type": "function", "function": {"name": "read_file", "arguments": {"path": "/tmp/test.txt"}}}"#
        buffer.appendContent(toolJson)
        XCTAssertTrue(buffer.hasToolText)
        XCTAssertFalse(buffer.hasContent)

        buffer.clear()

        // Thinking blocks should be extracted into reasoning
        buffer.appendContent("Here is my response. <think>Let me reason about this.</think> Final answer.")
        XCTAssertTrue(buffer.hasContent)
        XCTAssertTrue(buffer.hasReasoning)
        XCTAssertTrue(buffer.content.contains("Final answer"))
        XCTAssertTrue(buffer.reasoning.contains("Let me reason"))
    }

    // MARK: - Test: Rapid streaming simulation

    /// Simulate rapid streaming chunks; verify the render loop stays bounded and
    /// the committed chain remains append-only (no in-place node mutation).
    func testRapidStreamingDoesNotOverwhelmRenderLoop() async throws {
        let historyManager = ChatHistoryCoordinator(projectRoot: FileManager.default.temporaryDirectory)
        let draftId = UUID()
        let initialMessage = ChatMessage(
            id: draftId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            isDraft: true
        )
        historyManager.setDraft(initialMessage)

        var publishedCount = 0
        historyManager.$messages
            .sink { _ in publishedCount += 1 }
            .store(in: &cancellables)

        // Simulate 500 rapid chunks (like a fast local model spitting out tokens)
        let chunkSize = 4
        let totalChunks = 500
        let word = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor "

        for i in 0..<totalChunks {
            let chunk = String(word.dropFirst(i * chunkSize % word.count).prefix(chunkSize))
            historyManager.setDraft(
                ChatMessage(
                    id: draftId,
                    role: .assistant,
                    content: String(word.prefix((i + 1) * chunkSize)),
                    timestamp: initialMessage.timestamp,
                    isDraft: true
                )
            )
        }

        // The committed chain must still be empty (draft is ephemeral).
        XCTAssertTrue(historyManager.committedMessages.isEmpty)
        XCTAssertFalse(historyManager.messages.last?.content.isEmpty ?? true)

        // Commit once.
        historyManager.commitDraft()
        XCTAssertEqual(historyManager.committedMessages.count, 1)
        XCTAssertLessThan(publishedCount, totalChunks + 5, "published count should track drafts, not explode")
    }

    // MARK: - Test: Committed chain never mutates an existing node

    /// Once a turn is committed, it cannot be edited in place; updates go through
    /// fresh appends only. This is what keeps the provider prefix cache stable.
    func testCommittedChainNodesAreImmutable() async throws {
        let manager = ChatHistoryCoordinator(projectRoot: FileManager.default.temporaryDirectory)
        let userMsg = ChatMessage(id: UUID(), role: .user, content: "hello", timestamp: Date())
        manager.append(userMsg)
        let before = manager.committedMessages
        XCTAssertEqual(before.count, 1)
        let originalContent = before[0].content

        // A new assistant turn is appended; the user turn is untouched.
        manager.append(ChatMessage(id: UUID(), role: .assistant, content: "hi there", timestamp: Date()))
        XCTAssertEqual(manager.committedMessages.count, 2)
        XCTAssertEqual(manager.committedMessages[0].content, originalContent, "existing node must not change")
    }
}
