import XCTest
@testable import osx_ide

final class OpenRouterAPIClientTests: XCTestCase {
    func testSSEPayloadsJoinMultilineDataEvents() {
        let lines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"<think>\"}}",
            "data: ,\"usage\":{\"prompt_tokens\":1}}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}]}",
            "",
            "data: [DONE]"
        ]

        let payloads = OpenRouterAPIClient.ssePayloads(from: lines)

        XCTAssertEqual(payloads.count, 3)
        XCTAssertEqual(
            payloads[0],
            "{\"choices\":[{\"delta\":{\"content\":\"<think>\"}}\n,\"usage\":{\"prompt_tokens\":1}}"
        )
        XCTAssertEqual(payloads[1], "{\"choices\":[{\"delta\":{\"content\":\"done\"}}]}")
        XCTAssertEqual(payloads[2], "[DONE]")
    }

    func testOpenRouterServiceRecoversMinimaxToolCallMarkup() {
        let content = """
        Completed useTodos hook created Next: reviewing retrieved context and finalizing when the objective is satisfied in src/components.
        <minimax:tool_call>
        <invoke name="list_files">
        <parameter name="path">/tmp/project/src/components</parameter>
        </invoke>
        </minimax:tool_call>
        """

        let toolCalls = OpenRouterAIService.extractFallbackToolCalls(from: content)

        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "list_files")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "/tmp/project/src/components")
    }

    func testOpenRouterServiceRecoversStructuredXMLToolCallMarkup() {
        let content = """
        I'll create the package.json and test file now.
        <tool_call>
        <tool name="write_file">
        <arg name="path">/tmp/project/package.json</arg>
        <arg name="content">{"scripts":{"test":"vitest run"}}</arg>
        </tool>
        <tool name="create_file">
        <arg name="path">/tmp/project/src/utils.test.js</arg>
        <arg name="content">import { describe } from 'vitest'</arg>
        </tool>
        </tool_call>
        """

        let toolCalls = OpenRouterAIService.extractFallbackToolCalls(from: content)

        XCTAssertEqual(toolCalls?.count, 2)
        XCTAssertEqual(toolCalls?.first?.name, "write_file")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "/tmp/project/package.json")
        XCTAssertEqual(toolCalls?.last?.name, "write_file")
        XCTAssertEqual(toolCalls?.last?.arguments["path"] as? String, "/tmp/project/src/utils.test.js")
    }

    func testOpenRouterServiceRecoversStructuredXMLToolCallMarkupWithParameterTags() {
        let content = """
        <tool_call>
        <tool name="list_files">
        <parameter name="path">/tmp/project/src</parameter>
        </tool>
        </tool_call>
        """

        let toolCalls = OpenRouterAIService.extractFallbackToolCalls(from: content)

        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "list_files")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "/tmp/project/src")
    }

    func testOpenRouterServiceRecoversLegacyToolCodeMarkup() {
        let content = """
        <tool_code>
        list_files
        <param name="path">src/services</param>
        </tool_code>
        """

        let toolCalls = OpenRouterAIService.extractFallbackToolCalls(from: content)

        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "list_files")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "src/services")
    }

    func testOpenRouterServiceRecoversLegacySelfClosingToolMarkup() {
        let content = #"""
        <tool_code>
        <tool name="write_file"
        path="package.json"
        content="{&quot;name&quot;:&quot;utils-project&quot;}"
        />
        </tool_code>
        """#

        let toolCalls = OpenRouterAIService.extractFallbackToolCalls(from: content)

        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "write_file")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "package.json")
        XCTAssertEqual(toolCalls?.first?.arguments["content"] as? String, #"{"name":"utils-project"}"#)
    }

    func testOpenRouterServiceNormalizesRecoveredMinimaxToolAliases() {
        let content = """
        <minimax:tool_call>
        <invoke name="list_directory">
        <parameter name="path">/tmp/project</parameter>
        </invoke>
        <invoke name="cli-mcp-server_run_command">
        <parameter name="command">ls -la</parameter>
        </invoke>
        </minimax:tool_call>
        """

        let toolCalls = OpenRouterAIService.extractFallbackToolCalls(from: content)

        XCTAssertEqual(toolCalls?.count, 2)
        XCTAssertEqual(toolCalls?.first?.name, "list_files")
        XCTAssertEqual(toolCalls?.last?.name, "run_command")
        XCTAssertEqual(toolCalls?.last?.arguments["command"] as? String, "ls -la")
    }
}
