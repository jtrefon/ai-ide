import XCTest
@testable import osx_ide

final class TextualToolCallRecoveryTests: XCTestCase {
    func testChatPromptBuilderStripsTextualToolCallMarkupFromDisplay() {
        let raw = """
        I'll help you complete the dashboard implementation.
        <tool_call>read_file
        <arg_key>path</arg_key>
        <arg_value>/tmp/Dashboard.tsx</arg_value>
        </tool_call>
        """

        let display = ChatPromptBuilder.contentForDisplay(from: raw)

        XCTAssertFalse(display.contains("<tool_call>"))
        XCTAssertFalse(display.contains("<arg_key>"))
        XCTAssertFalse(display.contains("<arg_value>"))
        XCTAssertTrue(display.contains("I'll help you complete the dashboard implementation."))
    }

    func testChatPromptBuilderTreatsTextualToolCallMarkupAsIncompleteExecution() {
        let raw = """
        I'll help you complete the dashboard implementation.
        <tool_call>read_file
        <arg_key>path</arg_key>
        <arg_value>/tmp/Dashboard.tsx</arg_value>
        </tool_call>
        """

        XCTAssertTrue(ChatPromptBuilder.shouldForceToolFollowup(content: raw))
        XCTAssertTrue(
            ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: "please recover and continue implementing the dashboard",
                content: raw,
                hasToolCalls: false
            )
        )
    }

    func testLocalModelFallbackDoesNotRecoverXMLArgumentTagToolCall() {
        let raw = """
        I'll help you complete the dashboard implementation.
        <tool_call>read_file
        <arg_key>path</arg_key>
        <arg_value>/Users/jack/Projects/osx/osx-ide/sandbox/todo-app/src/components/Dashboard.tsx</arg_value>
        </tool_call>
        """

        let toolCalls = LocalModelProcessAIService.NativeMLXGenerator.extractFallbackToolCalls(
            from: raw,
            toolsWereProvided: true,
            structuredToolCallsWereDetected: false,
            toolCallFormat: .json
        )

        XCTAssertNil(toolCalls)
    }

    func testChatPromptBuilderTreatsMinimaxInvokeMarkupAsIncompleteExecution() {
        let raw = """
        <minimax:tool_call>
        <invoke name="cli-mcp-server_run_command">
        <parameter name="command">ls -la /tmp/project</parameter>
        </invoke>
        </minimax:tool_call>
        """

        XCTAssertTrue(ChatPromptBuilder.shouldForceToolFollowup(content: raw))
        XCTAssertTrue(
            ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: "continue implementing the task",
                content: raw,
                hasToolCalls: false
            )
        )
    }

    func testChatPromptBuilderStripsLegacyToolCodeMarkupFromDisplay() {
        let raw = """
        I am checking the project structure.
        <tool_code>
        list_files
        <param name="path">src/services</param>
        </tool_code>
        """

        let display = ChatPromptBuilder.contentForDisplay(from: raw)

        XCTAssertFalse(display.contains("<tool_code>"))
        XCTAssertFalse(display.contains("<param name="))
        XCTAssertTrue(display.contains("I am checking the project structure."))
    }

    func testChatPromptBuilderTreatsLegacyToolCodeMarkupAsIncompleteExecution() {
        let raw = """
        <tool_code>
        list_files
        <param name="path">src/models</param>
        </tool_code>
        """

        XCTAssertTrue(ChatPromptBuilder.shouldForceToolFollowup(content: raw))
        XCTAssertTrue(
            ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: "please continue reviewing the repository structure",
                content: raw,
                hasToolCalls: false
            )
        )
    }

    func testChatPromptBuilderDetectsMalformedInlineAttributeToolCall() {
        // The model emitted a `<tool_call name args>` opening tag (space, not `>`)
        // with a tool-name closing tag (`</read_file>`), which the engine must
        // recognize as textual tool-call markup so recovery fires instead of
        // delivering the pasted file contents as the answer.
        let raw = """
        Let me read the full Login component.
        <tool_call read_file tale-path="/Users/jack/Projects/osx/osx-ide/sandbox/todo-app/src/components/Login.tsx">
        </read_file>
        /Users/jack/Projects/osx/osx-ide/sandbox/todo-app/src/components/Login.tsx
        1
        300
        """

        XCTAssertTrue(
            ChatPromptBuilder.shouldForceToolFollowup(content: raw),
            "Malformed `<tool_call name=...>` opening tag must be detected"
        )
        XCTAssertTrue(
            ChatPromptBuilder.containsTextualToolCallMarkup(raw),
            "containsTextualToolCallMarkup must match the malformed opening tag"
        )
        let display = ChatPromptBuilder.contentForDisplay(from: raw)
        XCTAssertFalse(display.contains("<tool_call"), "Malformed tool-call markup must be stripped from display")
        XCTAssertFalse(display.contains("</read_file>"), "Malformed closing tag must be stripped from display")
    }

    func testToolLoopUtilitiesDetectsMalformedInlineAttributeToolCall() {
        let raw = """
        <tool_call read_file tale-path="/tmp/App.tsx">
        </read_file>
        """
        XCTAssertTrue(
            ToolLoopUtilities.containsLiteralToolCallMarkup(raw),
            "ToolLoopUtilities must detect the malformed `<tool_call name=...>` opening tag"
        )
    }
}
