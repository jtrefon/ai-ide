import XCTest
import Combine

@testable import osx_ide

@MainActor
final class ConversationSendCoordinatorTests: XCTestCase {
    private final class MockEventBus: EventBusProtocol {
        func publish<E: Event>(_ event: E) {}
        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            return AnyCancellable {}
        }
    }
    
    private final class SequenceAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [AIServiceResponse]

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(
            _ request: AIServiceMessageWithProjectRootRequest
        ) async throws -> AIServiceResponse {
            _ = request
            return dequeueResponse()
        }

        func sendMessage(
            _ request: AIServiceHistoryRequest
        ) async throws -> AIServiceResponse {
            _ = request
            return dequeueResponse()
        }

        func explainCode(_ code: String) async throws -> String {
            _ = code
            return "Explanation"
        }

        func refactorCode(_ code: String, instructions: String) async throws -> String {
            _ = code
            _ = instructions
            return "Refactored"
        }

        func generateCode(_ prompt: String) async throws -> String {
            _ = prompt
            return "Generated"
        }

        func fixCode(_ code: String, error: String) async throws -> String {
            _ = code
            _ = error
            return "Fixed"
        }

        private func dequeueResponse() -> AIServiceResponse {
            lock.lock()
            defer { lock.unlock() }
            guard !responses.isEmpty else {
                return AIServiceResponse(content: "(no more responses)", toolCalls: nil)
            }
            return responses.removeFirst()
        }
    }

    private final class SpyAIService: AIService, @unchecked Sendable {
        private let lock = AsyncLock()
        private(set) var historyRequests: [AIServiceHistoryRequest] = []
        private(set) var messageRequests: [AIServiceMessageWithProjectRootRequest] = []

        let response: AIServiceResponse

        init(response: AIServiceResponse) {
            self.response = response
        }

        func sendMessage(
            _ request: AIServiceMessageWithProjectRootRequest
        ) async throws -> AIServiceResponse {
            await lock.lock()
            messageRequests.append(request)
            await lock.unlock()
            return response
        }

        func sendMessage(
            _ request: AIServiceHistoryRequest
        ) async throws -> AIServiceResponse {
            await lock.lock()
            historyRequests.append(request)
            await lock.unlock()
            return response
        }

        func explainCode(_ code: String) async throws -> String {
            _ = code
            return "Explanation"
        }

        func refactorCode(_ code: String, instructions: String) async throws -> String {
            _ = code
            _ = instructions
            return "Refactored"
        }

        func generateCode(_ prompt: String) async throws -> String {
            _ = prompt
            return "Generated"
        }

        func fixCode(_ code: String, error: String) async throws -> String {
            _ = code
            _ = error
            return "Fixed"
        }
    }

    private final class FakeCodebaseIndex: CodebaseIndexProtocol {
        let currentEmbeddingModelIdentifier: String = "hashing_v1"
        private(set) var getSummariesCallCount: Int = 0
        private(set) var searchSymbolsWithPathsCallCount: Int = 0
        private(set) var getMemoriesCallCount: Int = 0

        let summaries: [(path: String, summary: String)]
        let symbolsByQuery: [String: [SymbolSearchResult]]
        let longTermMemories: [MemoryEntry]

        init(
            summaries: [(path: String, summary: String)],
            symbolsByQuery: [String: [SymbolSearchResult]],
            longTermMemories: [MemoryEntry]
        ) {
            self.summaries = summaries
            self.symbolsByQuery = symbolsByQuery
            self.longTermMemories = longTermMemories
        }

        func start() {}
        func stop() {}
        func setEnabled(_ enabled: Bool) { _ = enabled }
        func reindexProject() {}
        func reindexProject(aiEnrichmentEnabled: Bool) { _ = aiEnrichmentEnabled }
        func runAIEnrichment() {}
        func upgradeEmbeddingGenerator(_ generator: any MemoryEmbeddingGenerating) { }

        func listIndexedFiles(matching query: String?, limit: Int, offset: Int) async throws -> [String] {
            _ = query
            _ = limit
            _ = offset
            return []
        }

        func findIndexedFiles(query: String, limit: Int) async throws -> [IndexedFileMatch] {
            _ = query
            _ = limit
            return []
        }

        func readIndexedFile(path: String, startLine: Int?, endLine: Int?) throws -> String {
            _ = path
            _ = startLine
            _ = endLine
            return ""
        }

        func searchIndexedText(pattern: String, limit: Int) async throws -> [String] {
            _ = pattern
            _ = limit
            return []
        }

        func searchSymbols(nameLike query: String, limit: Int) async throws -> [Symbol] {
            _ = query
            _ = limit
            return []
        }

        func searchSymbolsWithPaths(nameLike query: String, limit: Int) async throws -> [SymbolSearchResult] {
            _ = limit
            searchSymbolsWithPathsCallCount += 1
            if let exact = symbolsByQuery[query] {
                return exact
            }

            let normalizedQuery = query.lowercased()
            if let normalized = symbolsByQuery.first(where: { $0.key.lowercased() == normalizedQuery })?.value {
                return normalized
            }

            return []
        }

        func getSummaries(projectRoot: URL, limit: Int) async throws -> [(path: String, summary: String)] {
            _ = projectRoot
            _ = limit
            getSummariesCallCount += 1
            return summaries
        }

        func getMemories(tier: MemoryTier?) async throws -> [MemoryEntry] {
            _ = tier
            getMemoriesCallCount += 1
            return longTermMemories
        }

        func addMemory(content: String, tier: MemoryTier, category: String) async throws -> MemoryEntry {
            _ = content
            _ = tier
            _ = category
            return MemoryEntry(id: UUID().uuidString, tier: tier, content: content, category: category, timestamp: Date(), protectionLevel: 0)
        }

        func getStats() async throws -> IndexStats {
            IndexStats(
                indexedResourceCount: 0,
                aiEnrichedResourceCount: 0,
                aiEnrichableProjectFileCount: 0,
                totalProjectFileCount: 0,
                symbolCount: 0,
                classCount: 0,
                structCount: 0,
                enumCount: 0,
                protocolCount: 0,
                functionCount: 0,
                variableCount: 0,
                memoryCount: 0,
                longTermMemoryCount: 0,
                databaseSizeBytes: 0,
                databasePath: "",
                isDatabaseInWorkspace: false,
                averageQualityScore: 0.0,
                averageAIQualityScore: 0.0
            )
        }
    }

    private struct FakeTool: AITool, @unchecked Sendable {
        let name: String
        let description: String = "fake"
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        let response: String

        func execute(arguments _: ToolArguments) async throws -> String {
            response
        }
    }

    func testSendExecutesToolLoopAndAppendsFinalAssistantMessage() async throws {
        let toolCallId = UUID().uuidString
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let toolCalls = [AIToolCall(id: toolCallId, name: "fake_tool", arguments: ["a": 1])]

        let aiService = makeSequenceAIService(toolCalls: toolCalls)
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot
        ))

        assertAssistantMessages(historyCoordinator: historyCoordinator)
        assertToolMessages(historyCoordinator: historyCoordinator, toolCallId: toolCallId)
    }

    func testSendRetriesWhenResponseContainsOnlyReasoning() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reasoningContent = reasoningOnlyContent()
        
        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: reasoningContent, toolCalls: nil),
            AIServiceResponse(content: "Final answer", toolCalls: nil)
        ])
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            userInput: "Foo Bar",
            availableTools: []
        ))
        
        // The retry should work and there should be an assistant message
        let assistantMessages = historyCoordinator.messages.filter { $0.role == .assistant }
        XCTAssertFalse(assistantMessages.isEmpty, "Should have at least one assistant message")
        
        // Check if the retry worked by looking for any non-empty assistant response
        let hasNonEmptyResponse = assistantMessages.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertTrue(hasNonEmptyResponse, "Should have a non-empty assistant response")
    }

    func testSendProvidesFallbackWhenResponseIsEmpty() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: "", toolCalls: nil),
            AIServiceResponse(content: "", toolCalls: nil)
        ])
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: []
        ))
        
        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && $0.content.contains("I wasn't able to generate a final response") })
        )
    }

    func testRAGContextIsInjectedDeterministicallyWhenIndexIsPresent() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let summaries: [(path: String, summary: String)] = [
            (path: projectRoot.appendingPathComponent("b.swift").path, summary: "B summary"),
            (path: projectRoot.appendingPathComponent("a.swift").path, summary: "A summary")
        ]

        let symbol1 = Symbol(
            id: UUID().uuidString,
            resourceId: "res1",
            name: "Foo",
            kind: .function,
            lineStart: 10,
            lineEnd: 20,
            description: nil
        )
        let symbol2 = Symbol(
            id: UUID().uuidString,
            resourceId: "res2",
            name: "Bar",
            kind: .class,
            lineStart: 1,
            lineEnd: 9,
            description: nil
        )

        let symbolsByQuery: [String: [SymbolSearchResult]] = [
            "Foo": [
                SymbolSearchResult(symbol: symbol1, filePath: projectRoot.appendingPathComponent("b.swift").path),
                SymbolSearchResult(symbol: symbol2, filePath: projectRoot.appendingPathComponent("a.swift").path)
            ]
        ]

        let longTermMemories = [
            MemoryEntry(id: "1", tier: .longTerm, content: "Z rule", category: "rules", timestamp: Date(), protectionLevel: 0),
            MemoryEntry(id: "2", tier: .longTerm, content: "A rule", category: "rules", timestamp: Date(), protectionLevel: 0)
        ]

        let fakeIndex = FakeCodebaseIndex(
            summaries: summaries,
            symbolsByQuery: symbolsByQuery,
            longTermMemories: longTermMemories
        )

        let aiService = SpyAIService(response: AIServiceResponse(content: "Done", toolCalls: nil))
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: "Foo"))
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot,
            codebaseIndex: fakeIndex
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            userInput: "Foo",
            availableTools: []
        ))

        let context = aiService.historyRequests.last?.context
        XCTAssertNotNil(context)

        let unwrappedContext = try XCTUnwrap(context)
        XCTAssertTrue(unwrappedContext.contains("RAG CONTEXT:"))
        XCTAssertTrue(unwrappedContext.contains("PROJECT OVERVIEW (Key Files):"))
        XCTAssertTrue(unwrappedContext.contains("CODEBASE INDEX (matching symbols):"))
        XCTAssertTrue(unwrappedContext.contains("PROJECT MEMORY (long-term rules):"))

        XCTAssertTrue(unwrappedContext.contains("- a.swift: A summary"))
        XCTAssertTrue(unwrappedContext.contains("- b.swift: B summary"))

        let overviewIndex = unwrappedContext.range(of: "PROJECT OVERVIEW")?.lowerBound
        let memoryIndex = unwrappedContext.range(of: "PROJECT MEMORY")?.lowerBound
        XCTAssertNotNil(overviewIndex)
        XCTAssertNotNil(memoryIndex)
        if let overviewIndex, let memoryIndex {
            XCTAssertLessThan(overviewIndex, memoryIndex)
        }

        XCTAssertGreaterThan(fakeIndex.getSummariesCallCount, 0)
        XCTAssertGreaterThan(fakeIndex.getMemoriesCallCount, 0)
        XCTAssertGreaterThan(fakeIndex.searchSymbolsWithPathsCallCount, 0)
    }

    private func makeSequenceAIService(toolCalls: [AIToolCall]) -> SequenceAIService {
        let completeReasoningPrefix =
            "<ide_reasoning>Analyze: Details\nResearch: Details\nPlan: Details\n" +
            "Reflect: Details\nAction: Call fake_tool\nDelivery: DONE</ide_reasoning>"
        let terminalResponses = Array(repeating: AIServiceResponse(
            content: completeReasoningPrefix + "Final answer",
            toolCalls: nil
        ), count: 12)
        return SequenceAIService(responses: [
            AIServiceResponse(content: completeReasoningPrefix + "Call tool", toolCalls: toolCalls),
        ] + terminalResponses)
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        let historyCoordinator = ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: "Hello"))
        return historyCoordinator
    }

    private func makeSendCoordinator(
        aiService: AIService,
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL,
        codebaseIndex: CodebaseIndexProtocol? = nil
    ) -> ConversationSendCoordinator {
        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: aiService, codebaseIndex: codebaseIndex, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        return ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )
    }

    private func makeSendRequest(
        conversationId: String,
        projectRoot: URL,
        userInput: String = "Hello",
        availableTools: [AITool] = [FakeTool(name: "fake_tool", response: "ok")],
        qaReviewEnabled: Bool = false,
        draftAssistantMessageId: UUID? = nil
    ) -> SendRequest {
        SendRequest(
            userInput: userInput,
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            qaReviewEnabled: qaReviewEnabled,
            draftAssistantMessageId: draftAssistantMessageId
        )
    }

    private func reasoningOnlyContent() -> String {
        """
        <ide_reasoning>
        Analyze: Details
        Research: Details
        Plan: Details
        Reflect: Details
        </ide_reasoning>
        """
    }

    private func assertAssistantMessages(historyCoordinator: ChatHistoryCoordinator) {
        print("History coordinator messages: \(historyCoordinator.messages)")
        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && $0.toolCalls?.isEmpty == false })
        )
        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && ($0.content.contains("Done") || $0.content.contains("Final answer")) })
        )
    }

    private func assertToolMessages(historyCoordinator: ChatHistoryCoordinator, toolCallId: String) {
        let toolMessages = historyCoordinator.messages.filter {
            $0.role == .tool && $0.toolCallId == toolCallId
        }

        let observedToolMessages = historyCoordinator.messages
            .filter { $0.role == .tool }
            .map {
                "\($0.toolName ?? "nil"):" +
                    "\($0.toolStatus?.rawValue ?? "nil"):" +
                    "\($0.toolCallId ?? "nil")"
            }

        XCTAssertFalse(
            toolMessages.isEmpty,
            "Expected tool messages for toolCallId=\(toolCallId). " +
                "Observed tool messages: \(observedToolMessages)"
        )

        let observedToolStatuses = toolMessages.map {
            "\($0.toolName ?? "nil"):" +
                "\($0.toolStatus?.rawValue ?? "nil")"
        }

        XCTAssertTrue(
            toolMessages.contains(where: { $0.toolStatus == .completed }),
            "Expected at least one completed tool message for toolCallId=\(toolCallId). " +
                "Observed: \(observedToolStatuses)"
        )
    }
}
