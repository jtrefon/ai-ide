import XCTest
@testable import osx_ide

final class ChatPromptBuilderReasoningTests: XCTestCase {
    func testSplitReasoning_extractsBlockAndCleansContent() {
        let input = """
        <ide_reasoning>
        Analyze: - A
        Research: - B
        Plan: - C
        Reflect: - D
        </ide_reasoning>

        Hello world
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertNotNil(split.reasoning)
        XCTAssertTrue(split.reasoning?.contains("Analyze:") == true)
        XCTAssertEqual(split.content, "Hello world")
    }

    func testIsLowQualityReasoning_detectsPlaceholder() {
        let input = """
        <ide_reasoning>
        Analyze: ...
        Research: ...
        Plan: ...
        Reflect: ...
        </ide_reasoning>

        Answer
        """

        XCTAssertTrue(ChatPromptBuilder.isLowQualityReasoning(text: input))
    }

    func testNeedsReasoningFormatCorrection_detectsMissingSection() {
        let input = """
        <ide_reasoning>
        Analyze: - A
        Research: - B
        Plan: - C
        </ide_reasoning>

        Answer
        """

        XCTAssertTrue(ChatPromptBuilder.needsReasoningFormatCorrection(text: input))
    }
}
