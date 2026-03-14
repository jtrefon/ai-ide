import XCTest
import Foundation
@testable import osx_ide

final class ChatPromptBuilderReasoningTests: XCTestCase {
    func testSplitReasoning_extractsBlockAndCleansContent() {
        let input = """
        Reflection:
        - What: A
        Planning:
        - What: B
        Continuity: D

        Hello world
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertNotNil(split.reasoning)
        XCTAssertTrue(split.reasoning?.contains("Reflection:") == true)
        XCTAssertEqual(split.content, "Hello world")
    }

    func testIsLowQualityReasoning_detectsPlaceholder() {
        let input = """
        Reflection: ...
        Planning: ...
        Continuity: ...

        Answer
        """

        XCTAssertTrue(ChatPromptBuilder.isLowQualityReasoning(text: input))
    }

    func testNeedsReasoningFormatCorrection_detectsMissingSection() {
        let input = """
        Reflection: A
        Planning: B

        Answer
        """

        XCTAssertFalse(ChatPromptBuilder.needsReasoningFormatCorrection(text: input))
    }

    func testSplitReasoningDoesNotStripPlainContentWithoutLeadingReasoningBlock() {
        let input = """
        Visible one
        Visible two
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Visible one\nVisible two")
        XCTAssertNil(split.reasoning)
    }

    func testSplitReasoning_stripsPlainLeadingReasoningBlockFromVisibleContent() {
        let input = """
        Reflection: Working
        Planning: Working
        Continuity: Stable

        Before content
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Before content")
        XCTAssertTrue(split.reasoning?.contains("Reflection: Working") == true)
    }

    func testSplitReasoning_extractsThinkingTagAndCleansContent() {
        let input = """
        <thinking>
        Reflection: A
        Planning: B
        Continuity: C
        </thinking>

        Visible answer
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Visible answer")
        XCTAssertEqual(split.reasoning, "Reflection: A\nPlanning: B\nContinuity: C")
    }

    func testSplitReasoning_extractsThinkTagAndCleansContent() {
        let input = """
        <think>
        Reflection: A
        Planning: B
        Continuity: C
        </think>

        Visible answer
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Visible answer")
        XCTAssertEqual(split.reasoning, "Reflection: A\nPlanning: B\nContinuity: C")
    }

    func testSplitReasoning_extractsLegacyIdeReasoningTagAndCleansContent() {
        let input = """
        <ide_reasoning>
        Reflection: A
        Planning: B
        Continuity: C
        </ide_reasoning>

        Visible answer
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Visible answer")
        XCTAssertEqual(split.reasoning, "Reflection: A\nPlanning: B\nContinuity: C")
    }

    func testSplitReasoningLeavesInlineContentUntouchedWithoutTaggedMarkupSupport() {
        let input = "Alpha Reflection: R Beta"
        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Alpha Reflection: R Beta")
        XCTAssertNil(split.reasoning)
    }

    func testContentForDisplayLeavesUnsupportedXMLLookingTextUntouched() {
        let input = """
        <tool_call>read_file
        <arg_key>path</arg_key>
        <arg_value>prisma/schema.prisma</arg_value>
        </tool_call>
        Done exploring structure.
        """

        let output = ChatPromptBuilder.contentForDisplay(from: input)
        XCTAssertTrue(output.contains("<tool_call>read_file"))
        XCTAssertTrue(output.contains("Done exploring structure."))
    }

    func testIsControlMarkupOnlyReturnsFalseForUnsupportedXMLLookingText() {
        let input = """
        <tool_call>list_files
        <arg_key>path</arg_key>
        <arg_value>/tmp</arg_value>
        </tool_call>
        """
        XCTAssertFalse(ChatPromptBuilder.isControlMarkupOnly(input))
    }

    func testHasMissingClaimedFileArtifactsDetectsMissingFiles() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("chat_prompt_builder_missing_artifact_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let content = "Created React Todo app with package.json, index.html, src/main.jsx, and src/App.jsx."
        try "{}".write(to: tempRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        XCTAssertTrue(
            ChatPromptBuilder.hasMissingClaimedFileArtifacts(content: content, projectRoot: tempRoot),
            "Expected claimed scaffold files missing on disk to be detected"
        )
    }

    func testHasMissingClaimedFileArtifactsReturnsFalseWhenClaimedFilesExist() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("chat_prompt_builder_existing_artifact_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("src"),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try "{}".write(to: tempRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: tempRoot.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "console.log('main')".write(to: tempRoot.appendingPathComponent("src/main.jsx"), atomically: true, encoding: .utf8)
        try "export default function App() {}".write(to: tempRoot.appendingPathComponent("src/App.jsx"), atomically: true, encoding: .utf8)

        let content = "Created React Todo app with package.json, index.html, src/main.jsx, and src/App.jsx."

        XCTAssertFalse(
            ChatPromptBuilder.hasMissingClaimedFileArtifacts(content: content, projectRoot: tempRoot),
            "Expected no missing artifacts when all claimed files exist"
        )
    }

    func testShouldForceExecutionFollowupForDoneNextPendingWorkResponse() {
        let shouldForce = ChatPromptBuilder.shouldForceExecutionFollowup(
            userInput: "Create package.json, index.html, src/main.jsx, and src/App.jsx using tools.",
            content: "Done → Next: Create index.html, src/main.jsx, src/App.jsx → Path: write_files",
            hasToolCalls: false
        )

        XCTAssertTrue(
            shouldForce,
            "Expected Done → Next pending-work responses to continue forcing execution followup"
        )
    }

    func testIndicatesWorkWasPerformedForScaffoldCompletionSummary() {
        let content = "Done. All required files have been created and the React Todo application structure is now in place."

        XCTAssertTrue(
            ChatPromptBuilder.indicatesWorkWasPerformed(content: content),
            "Expected scaffold completion summaries to count as performed work"
        )
    }
}
