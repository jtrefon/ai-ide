import XCTest
@testable import osx_ide

@MainActor
final class RAGContextBuilderTests: XCTestCase {

    // MARK: - No retriever

    func testBuildContextWithNoRetrieverAndNoExplicitContextReturnsNil() async {
        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: nil,
            retriever: nil,
            projectRoot: nil
        )
        XCTAssertNil(result)
    }

    func testBuildContextWithNoRetrieverReturnsExplicitContextOnly() async {
        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: "some context",
            retriever: nil,
            projectRoot: nil
        )
        XCTAssertEqual(result, "some context")
    }

    func testBuildContextWithWhitespaceExplicitContextReturnsNil() async {
        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: "   \n\t ",
            retriever: nil,
            projectRoot: nil
        )
        XCTAssertNil(result)
    }

    // MARK: - With retriever

    func testBuildContextIncludesRAGBlockWhenRetrieverReturnsData() async {
        let retriever = StubRAGRetriever(result: RAGRetrievalResult(
            projectOverviewLines: ["- README.md: project overview"],
            symbolLines: ["- [function] doSomething (src/main.swift:10-20)"],
            memoryLines: ["- always use tabs"]
        ))

        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: nil,
            retriever: retriever,
            projectRoot: nil
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("RAG CONTEXT:"))
        XCTAssertTrue(result!.contains("PROJECT OVERVIEW"))
        XCTAssertTrue(result!.contains("CODEBASE INDEX"))
        XCTAssertTrue(result!.contains("PROJECT MEMORY"))
        XCTAssertTrue(result!.contains("README.md"))
        XCTAssertTrue(result!.contains("doSomething"))
        XCTAssertTrue(result!.contains("always use tabs"))
    }

    func testBuildContextCombinesExplicitContextAndRAGBlock() async {
        let retriever = StubRAGRetriever(result: RAGRetrievalResult(
            projectOverviewLines: ["- file.swift: entry point"],
            symbolLines: [],
            memoryLines: []
        ))

        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: "explicit info",
            retriever: retriever,
            projectRoot: nil
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("explicit info"))
        XCTAssertTrue(result!.contains("RAG CONTEXT:"))
    }

    func testBuildContextWithEmptyRetrieverResultAndNoExplicitContextReturnsNil() async {
        let retriever = StubRAGRetriever(result: .empty)

        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: nil,
            retriever: retriever,
            projectRoot: nil
        )

        XCTAssertNil(result)
    }

    func testBuildContextWithEmptyRetrieverResultReturnsExplicitContextOnly() async {
        let retriever = StubRAGRetriever(result: .empty)

        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: "explicit only",
            retriever: retriever,
            projectRoot: nil
        )

        XCTAssertEqual(result, "explicit only")
    }

    func testBuildContextOmitsSectionsWithNoData() async {
        let retriever = StubRAGRetriever(result: RAGRetrievalResult(
            projectOverviewLines: [],
            symbolLines: ["- [class] Foo (bar.swift:1-10)"],
            memoryLines: []
        ))

        let result = await RAGContextBuilder.buildContext(
            userInput: "hello",
            explicitContext: nil,
            retriever: retriever,
            projectRoot: nil
        )

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.contains("PROJECT OVERVIEW"))
        XCTAssertTrue(result!.contains("CODEBASE INDEX"))
        XCTAssertFalse(result!.contains("PROJECT MEMORY"))
    }
}

@MainActor
private final class StubRAGRetriever: RAGRetriever {
    private let result: RAGRetrievalResult

    init(result: RAGRetrievalResult) {
        self.result = result
    }

    func retrieve(_ request: RAGRetrievalRequest) async -> RAGRetrievalResult {
        _ = request
        return result
    }
}
