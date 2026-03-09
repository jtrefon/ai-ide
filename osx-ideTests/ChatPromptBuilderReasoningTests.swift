import XCTest
import Foundation
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

    func testSplitReasoning_removesMultipleTaggedBlocks() {
        let input = """
        <ide_reasoning>
        Reflection: First
        Planning: First
        Continuity: First
        </ide_reasoning>
        Visible one
        <ide_reasoning>
        Reflection: Second
        Planning: Second
        Continuity: Second
        </ide_reasoning>
        Visible two
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Visible one\n\nVisible two")
        XCTAssertTrue(split.reasoning?.contains("Reflection: First") == true)
        XCTAssertTrue(split.reasoning?.contains("Reflection: Second") == true)
    }

    func testSplitReasoning_stripsIncompleteTaggedBlockFromVisibleContent() {
        let input = """
        Before content
        <ide_reasoning>
        Reflection: Working
        Planning: Working
        """

        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Before content")
        XCTAssertTrue(split.reasoning?.contains("Reflection: Working") == true)
    }

    func testSplitReasoning_preservesWordSeparationAroundTaggedBlock() {
        let input = "Alpha<ide_reasoning>Reflection: R</ide_reasoning>Beta"
        let split = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(split.content, "Alpha\n\nBeta")
        XCTAssertEqual(split.reasoning, "Reflection: R")
    }

    func testContentForDisplay_stripsToolControlMarkup() {
        let input = """
        <tool_call>read_file
        <arg_key>path</arg_key>
        <arg_value>prisma/schema.prisma</arg_value>
        </tool_call>
        Done exploring structure.
        """

        let output = ChatPromptBuilder.contentForDisplay(from: input)
        XCTAssertEqual(output, "Done exploring structure.")
    }

    func testIsControlMarkupOnly_detectsPureToolMarkup() {
        let input = """
        <tool_call>list_files
        <arg_key>path</arg_key>
        <arg_value>/tmp</arg_value>
        </tool_call>
        """
        XCTAssertTrue(ChatPromptBuilder.isControlMarkupOnly(input))
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
