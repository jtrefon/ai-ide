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
}
