import XCTest
@testable import osx_ide

final class RAGContextBuilderTests: XCTestCase {
    
    // MARK: - Context Packing Tests
    
    func testBuildsContextWithExplicitContextOnly() async {
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: "Explicit context content",
            retriever: nil,
            projectRoot: nil
        )
        
        XCTAssertEqual(context, "Explicit context content")
    }
    
    func testTrimsWhitespaceFromExplicitContext() async {
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: "  \n  Trimmed content  \n  ",
            retriever: nil,
            projectRoot: nil
        )
        
        XCTAssertEqual(context, "Trimmed content")
    }
    
    func testReturnsNilForEmptyExplicitContext() async {
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: "   ",
            retriever: nil,
            projectRoot: nil
        )
        
        XCTAssertNil(context)
    }
    
    func testReturnsNilForNilExplicitContextAndNoRetriever() async {
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: nil,
            projectRoot: nil
        )
        
        XCTAssertNil(context)
    }
    
    func testCombinesExplicitContextWithRAGContext() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["symbol1", "symbol2"],
            overviewLines: ["overview1"],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: "Explicit content",
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("Explicit content") ?? false)
        XCTAssertTrue(context?.contains("RAG CONTEXT") ?? false)
    }
    
    // MARK: - Section Formatting Tests
    
    func testFormatsProjectOverviewSection() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: [],
            overviewLines: ["README.md: Project description", "ARCHITECTURE.md: System design"],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("PROJECT OVERVIEW (Key Files):") ?? false)
        XCTAssertTrue(context?.contains("README.md: Project description") ?? false)
        XCTAssertTrue(context?.contains("ARCHITECTURE.md: System design") ?? false)
    }
    
    func testFormatsCodebaseIndexSection() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["AuthService.authenticate()", "UserModel.validate()"],
            overviewLines: [],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("CODEBASE INDEX (matching symbols):") ?? false)
        XCTAssertTrue(context?.contains("AuthService.authenticate()") ?? false)
        XCTAssertTrue(context?.contains("UserModel.validate()") ?? false)
    }
    
    func testFormatsProjectMemorySection() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: [],
            overviewLines: [],
            memoryLines: ["Use dependency injection", "Follow SOLID principles"],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("PROJECT MEMORY (long-term rules):") ?? false)
        XCTAssertTrue(context?.contains("Use dependency injection") ?? false)
        XCTAssertTrue(context?.contains("Follow SOLID principles") ?? false)
    }
    
    func testFormatsCodeSegmentsSection() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: [],
            overviewLines: [],
            memoryLines: [],
            segmentLines: ["func authenticate() { ... }", "class UserService { ... }"],
            reuseCandidateLines: []
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("CODE SEGMENTS (high-signal snippets):") ?? false)
        XCTAssertTrue(context?.contains("func authenticate() { ... }") ?? false)
        XCTAssertTrue(context?.contains("class UserService { ... }") ?? false)
    }
    
    func testFormatsReuseCandidatesSection() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: [],
            overviewLines: [],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: ["ExistingAuthService", "ExistingValidator"]
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("REUSE CANDIDATES (must consider before new implementation):") ?? false)
        XCTAssertTrue(context?.contains("ExistingAuthService") ?? false)
        XCTAssertTrue(context?.contains("ExistingValidator") ?? false)
    }
    
    func testFormatsMultipleSections() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["AuthService"],
            overviewLines: ["README.md"],
            memoryLines: ["Use DI"],
            segmentLines: ["func auth() {}"],
            reuseCandidateLines: ["ExistingAuth"]
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("PROJECT OVERVIEW") ?? false)
        XCTAssertTrue(context?.contains("CODEBASE INDEX") ?? false)
        XCTAssertTrue(context?.contains("PROJECT MEMORY") ?? false)
        XCTAssertTrue(context?.contains("CODE SEGMENTS") ?? false)
        XCTAssertTrue(context?.contains("REUSE CANDIDATES") ?? false)
    }
    
    func testSectionsSeparatedByDoubleNewlines() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["symbol"],
            overviewLines: ["overview"],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        let context = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test")
        )
        
        XCTAssertNotNil(context)
        let sections = context?.components(separatedBy: "\n\n") ?? []
        XCTAssertGreaterThan(sections.count, 1, "Sections should be separated by double newlines")
    }
    
    // MARK: - Stage and Conversation Metadata Tests
    
    func testPassesStageToRetriever() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["test"],
            overviewLines: [],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        _ = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test"),
            stage: .toolLoop,
            conversationId: nil
        )
        
        XCTAssertEqual(mockRetriever.lastRequest?.stage, "tool_loop")
    }
    
    func testPassesConversationIdToRetriever() async {
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["test"],
            overviewLines: [],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        let conversationId = "test-conversation-123"
        _ = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test"),
            stage: nil,
            conversationId: conversationId
        )
        
        XCTAssertEqual(mockRetriever.lastRequest?.conversationId, conversationId)
    }
    
    // MARK: - Event Publishing Tests
    
    func testPublishesRetrievalStartedEvent() async {
        let mockEventBus = MockEventBus()
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["test"],
            overviewLines: [],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        _ = await RAGContextBuilder.buildContext(
            userInput: "test input",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test"),
            eventBus: mockEventBus
        )
        
        let startedEvents = mockEventBus.publishedEvents.compactMap { $0 as? RAGRetrievalStartedEvent }
        XCTAssertEqual(startedEvents.count, 1)
        XCTAssertEqual(startedEvents.first?.userInputPreview, "test input")
    }
    
    func testPublishesRetrievalEvidencePreparedEvent() async {
        let mockEventBus = MockEventBus()
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["test"],
            overviewLines: [],
            memoryLines: [],
            segmentLines: [],
            reuseCandidateLines: [],
            evidenceCount: 5,
            retrievalConfidence: 0.85
        )
        
        _ = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test"),
            eventBus: mockEventBus
        )
        
        let evidenceEvents = mockEventBus.publishedEvents.compactMap { $0 as? RetrievalEvidencePreparedEvent }
        XCTAssertEqual(evidenceEvents.count, 1)
        XCTAssertEqual(evidenceEvents.first?.evidenceCount, 5)
        XCTAssertEqual(evidenceEvents.first?.retrievalConfidence, 0.85)
    }
    
    func testPublishesRetrievalCompletedEvent() async {
        let mockEventBus = MockEventBus()
        let mockRetriever = MockRAGRetriever(
            symbolLines: ["s1", "s2"],
            overviewLines: ["o1"],
            memoryLines: ["m1"],
            segmentLines: [],
            reuseCandidateLines: []
        )
        
        _ = await RAGContextBuilder.buildContext(
            userInput: "test",
            explicitContext: nil,
            retriever: mockRetriever,
            projectRoot: URL(fileURLWithPath: "/test"),
            eventBus: mockEventBus
        )
        
        let completedEvents = mockEventBus.publishedEvents.compactMap { $0 as? RAGRetrievalCompletedEvent }
        XCTAssertEqual(completedEvents.count, 1)
        XCTAssertEqual(completedEvents.first?.symbolCount, 2)
        XCTAssertEqual(completedEvents.first?.overviewCount, 1)
        XCTAssertEqual(completedEvents.first?.memoryCount, 1)
    }
}

// MARK: - Mock Implementations

private class MockRAGRetriever: RAGRetriever {
    let symbolLines: [String]
    let overviewLines: [String]
    let memoryLines: [String]
    let segmentLines: [String]
    let reuseCandidateLines: [String]
    let evidenceCount: Int
    let retrievalConfidence: Double
    var lastRequest: RAGRetrievalRequest?
    
    init(
        symbolLines: [String],
        overviewLines: [String],
        memoryLines: [String],
        segmentLines: [String],
        reuseCandidateLines: [String],
        evidenceCount: Int = 0,
        retrievalConfidence: Double = 0.0
    ) {
        self.symbolLines = symbolLines
        self.overviewLines = overviewLines
        self.memoryLines = memoryLines
        self.segmentLines = segmentLines
        self.reuseCandidateLines = reuseCandidateLines
        self.evidenceCount = evidenceCount
        self.retrievalConfidence = retrievalConfidence
    }
    
    func retrieve(_ request: RAGRetrievalRequest) async -> RAGRetrievalResult {
        lastRequest = request
        return RAGRetrievalResult(
            projectOverviewLines: overviewLines,
            symbolLines: symbolLines,
            memoryLines: memoryLines,
            segmentLines: segmentLines,
            reuseCandidateLines: reuseCandidateLines,
            evidenceCards: Array(repeating: EvidenceCard(
                filePath: "test.swift",
                evidenceType: .symbol,
                lineStart: 1,
                lineEnd: 10,
                preview: "test",
                totalScore: 0.5,
                scoreComponents: EvidenceScoreComponents(
                    semanticSimilarity: 0.5,
                    intentWeight: 0.0,
                    architectureProximity: 0.0,
                    qualityBoost: 0.0,
                    recency: 0.0,
                    stalenessPenalty: 0.0
                )
            ), count: evidenceCount),
            intent: .other,
            retrievalConfidence: retrievalConfidence
        )
    }
}

private class MockEventBus: EventBusProtocol {
    var publishedEvents: [any AppEvent] = []
    
    func publish(_ event: any AppEvent) {
        publishedEvents.append(event)
    }
    
    func subscribe<T: AppEvent>(_ eventType: T.Type, handler: @escaping (T) -> Void) -> EventSubscription {
        return EventSubscription(id: UUID(), unsubscribe: {})
    }
}
