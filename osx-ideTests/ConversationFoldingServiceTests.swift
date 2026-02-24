import XCTest
@testable import osx_ide

@MainActor
final class ConversationFoldingServiceTests: XCTestCase {

    // MARK: - shouldFold

    func testShouldFoldReturnsFalseWhenBelowThresholds() {
        let messages = makeMessages(count: 5, contentLength: 10)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 40, maxContentCharacters: 20_000, preserveMostRecentMessages: 20)
        XCTAssertFalse(ConversationFoldingService.shouldFold(messages: messages, thresholds: thresholds))
    }

    func testShouldFoldReturnsTrueWhenMessageCountExceedsThreshold() {
        let messages = makeMessages(count: 50, contentLength: 10)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 40, maxContentCharacters: 200_000, preserveMostRecentMessages: 20)
        XCTAssertTrue(ConversationFoldingService.shouldFold(messages: messages, thresholds: thresholds))
    }

    func testShouldFoldReturnsTrueWhenContentCharactersExceedThreshold() {
        let messages = makeMessages(count: 5, contentLength: 5000)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 100, maxContentCharacters: 1000, preserveMostRecentMessages: 2)
        XCTAssertTrue(ConversationFoldingService.shouldFold(messages: messages, thresholds: thresholds))
    }

    // MARK: - fold

    func testFoldReturnsNilWhenBelowThresholds() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let messages = makeMessages(count: 5, contentLength: 10)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 40, maxContentCharacters: 20_000, preserveMostRecentMessages: 20)

        let result = try await ConversationFoldingService.fold(messages: messages, projectRoot: projectRoot, thresholds: thresholds)
        XCTAssertNil(result)
    }

    func testFoldReturnsResultWhenAboveThresholds() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let messages = makeMessages(count: 50, contentLength: 10)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 40, maxContentCharacters: 200_000, preserveMostRecentMessages: 20)

        let result = try await ConversationFoldingService.fold(messages: messages, projectRoot: projectRoot, thresholds: thresholds)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.foldedMessageCount, 30)
        XCTAssertFalse(result!.entry.summary.isEmpty)
    }

    func testFoldReturnsNilWhenNotEnoughMessagesToPreserve() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let messages = makeMessages(count: 5, contentLength: 5000)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 2, maxContentCharacters: 100, preserveMostRecentMessages: 10)

        let result = try await ConversationFoldingService.fold(messages: messages, projectRoot: projectRoot, thresholds: thresholds)
        XCTAssertNil(result)
    }

    func testFoldSummaryContainsContextSummaryHeader() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let messages = makeMessages(count: 50, contentLength: 10)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 40, maxContentCharacters: 200_000, preserveMostRecentMessages: 20)

        let result = try await ConversationFoldingService.fold(messages: messages, projectRoot: projectRoot, thresholds: thresholds)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.entry.summary.contains("Context summary"))
    }

    func testFoldSummaryExcludesReasoningBlocks() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        var messages: [ChatMessage] = []
        for i in 0..<50 {
            let role: MessageRole = (i % 2 == 0) ? .user : .assistant
            let content = "Message \(i)"
            let context = ChatMessageContentContext(reasoning: "<ide_reasoning>secret reasoning</ide_reasoning>", codeContext: nil)
            messages.append(ChatMessage(role: role, content: content, context: context))
        }
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 40, maxContentCharacters: 200_000, preserveMostRecentMessages: 20)

        let result = try await ConversationFoldingService.fold(messages: messages, projectRoot: projectRoot, thresholds: thresholds)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.entry.summary.contains("<ide_reasoning>"))
    }

    func testFoldWritesToStore() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let messages = makeMessages(count: 50, contentLength: 10)
        let thresholds = ConversationFoldingThresholds(maxMessageCount: 40, maxContentCharacters: 200_000, preserveMostRecentMessages: 20)

        let result = try await ConversationFoldingService.fold(messages: messages, projectRoot: projectRoot, thresholds: thresholds)
        XCTAssertNotNil(result)

        let store = ConversationFoldStore(projectRoot: projectRoot)
        let entries = try await store.list(limit: 10)
        XCTAssertTrue(entries.contains(where: { $0.id == result!.entry.id }))
    }

    // MARK: - Helpers

    private func makeMessages(count: Int, contentLength: Int) -> [ChatMessage] {
        (0..<count).map { i in
            let role: MessageRole = (i % 2 == 0) ? .user : .assistant
            let content = String(repeating: "x", count: contentLength)
            return ChatMessage(role: role, content: content)
        }
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_fold_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
