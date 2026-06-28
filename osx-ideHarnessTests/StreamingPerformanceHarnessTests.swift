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

    // MARK: - Test: ChatHistoryManager draft coalescing

    /// Verify that upsertDraftMessage coalesces rapid updates and doesn't fire @Published on every call.
    func testDraftUpdateCoalescingReducesPublishedFires() async throws {
        let manager = ChatHistoryManager()
        let draftId = UUID()
        let initialMessage = ChatMessage(
            id: draftId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            isDraft: true
        )
        manager.messages = [initialMessage]

        var publishedCount = 0
        manager.$messages
            .removeDuplicates(by: { $0.count == $1.count && $0.last?.content == $1.last?.content })
            .sink { _ in publishedCount += 1 }
            .store(in: &cancellables)

        // Simulate 100 rapid draft updates (as if streaming 100 chunks in quick succession)
        for i in 0..<100 {
            manager.upsertDraftMessage(
                ChatMessage(
                    id: draftId,
                    role: .assistant,
                    content: "chunk \(i) ",
                    timestamp: initialMessage.timestamp,
                    isDraft: true
                )
            )
        }

        // Wait beyond coalesce interval for the last update to fire
        try await Task.sleep(nanoseconds: 200_000_000)

        // With coalescing at 150ms, 100 rapid updates should produce at most 1-2 @Published fires
        // (the initial value + at most 1 coalesced publish)
        XCTAssertLessThan(
            publishedCount,
            5,
            "Expected at most a few @Published fires for 100 rapid draft updates, got \(publishedCount)"
        )

        // Verify final content is correct (last update wins)
        manager.flushPendingDraftUpdate()
        XCTAssertEqual(manager.messages.last?.content, "chunk 99 ")
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

    /// Simulate rapid streaming chunks and verify the render loop doesn't overwhelm the system.
    func testRapidStreamingDoesNotOverwhelmRenderLoop() async throws {
        let historyManager = ChatHistoryManager()
        let draftId = UUID()
        let initialMessage = ChatMessage(
            id: draftId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            isDraft: true
        )
        historyManager.messages = [initialMessage]

        var publishedCount = 0
        historyManager.$messages
            .removeDuplicates(by: { $0.count == $1.count && $0.last?.content == $1.last?.content })
            .sink { _ in publishedCount += 1 }
            .store(in: &cancellables)

        // Simulate 500 rapid chunks (like a fast local model spitting out tokens)
        let chunkSize = 4
        let totalChunks = 500
        let word = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor "

        for i in 0..<totalChunks {
            let chunk = String(word.dropFirst(i * chunkSize % word.count).prefix(chunkSize))
            historyManager.upsertDraftMessage(
                ChatMessage(
                    id: draftId,
                    role: .assistant,
                    content: String(word.prefix((i + 1) * chunkSize)),
                    timestamp: initialMessage.timestamp,
                    isDraft: true
                )
            )
        }

        // Wait for coalesce
        try await Task.sleep(nanoseconds: 250_000_000)
        historyManager.flushPendingDraftUpdate()

        // With 150ms coalescing, 500 rapid updates over ~0ms should produce very few publishes
        XCTAssertLessThan(
            publishedCount,
            10,
            "Expected fewer than 10 @Published fires for 500 rapid chunks, got \(publishedCount)"
        )

        // Verify final content is present
        XCTAssertFalse(historyManager.messages.last?.content.isEmpty ?? true)
    }

    // MARK: - Test: Coalesce interval timing

    /// Verify that draft updates are published at most once per coalesce interval.
    func testCoalesceIntervalBoundsPublishFrequency() async throws {
        let manager = ChatHistoryManager()
        let draftId = UUID()
        let initialMessage = ChatMessage(
            id: draftId,
            role: .assistant,
            content: "",
            timestamp: Date(),
            isDraft: true
        )
        manager.messages = [initialMessage]

        var publishedCount = 0
        manager.$messages
            .removeDuplicates(by: { $0.count == $1.count && $0.last?.content == $1.last?.content })
            .sink { _ in publishedCount += 1 }
            .store(in: &cancellables)

        // Send updates over ~500ms with 150ms coalesce interval
        // Expected: at most ~4 publishes (500ms / 150ms ≈ 3-4)
        for i in 0..<10 {
            manager.upsertDraftMessage(
                ChatMessage(
                    id: draftId,
                    role: .assistant,
                    content: "update \(i)",
                    timestamp: initialMessage.timestamp,
                    isDraft: true
                )
            )
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms between updates
        }

        // Wait for final coalesce
        try await Task.sleep(nanoseconds: 200_000_000)
        manager.flushPendingDraftUpdate()

        XCTAssertLessThan(
            publishedCount,
            8,
            "Expected at most ~4-5 publishes for 10 updates over 500ms with 150ms coalesce, got \(publishedCount)"
        )
    }
}
