import XCTest
@testable import osx_ide

final class ToolCallFallbackParserTests: XCTestCase {
    private let parser = ToolCallFallbackParser()

    // MARK: - Structured XML

    func testDecodesStructuredXMLToolCallMarkup() {
        let content = """
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
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 2)
        XCTAssertEqual(toolCalls?.first?.name, "write")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "/tmp/project/package.json")
        XCTAssertEqual(toolCalls?.last?.name, "write")
        XCTAssertEqual(toolCalls?.last?.arguments["path"] as? String, "/tmp/project/src/utils.test.js")
    }

    func testDecodesStructuredXMLWithParameterTags() {
        let content = """
        <tool_call>
        <tool name="list_files">
        <parameter name="path">/tmp/project/src</parameter>
        </tool>
        </tool_call>
        """
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "ls")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "/tmp/project/src")
    }

    // MARK: - Legacy Tool Code

    func testDecodesLegacyToolCodeMarkup() {
        let content = """
        <tool_code>
        list_files
        <param name="path">src/services</param>
        </tool_code>
        """
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "ls")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "src/services")
    }

    func testDecodesLegacySelfClosingToolMarkup() {
        let content = #"""
        <tool_code>
        <tool name="write_file"
        path="package.json"
        content="{&quot;name&quot;:&quot;utils-project&quot;}"
        />
        </tool_code>
        """#
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "write")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "package.json")
        XCTAssertEqual(toolCalls?.first?.arguments["content"] as? String, #"{"name":"utils-project"}"#)
    }

    // MARK: - Minimax

    func testDecodesMinimaxToolCalls() {
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
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 2)
        XCTAssertEqual(toolCalls?.first?.name, "ls")
        XCTAssertEqual(toolCalls?.last?.name, "bash")
        XCTAssertEqual(toolCalls?.last?.arguments["command"] as? String, "ls -la")
    }

    // MARK: - Gemma Format

    func testDecodesGemmaFormatToolCalls() {
        let content = #"""
        <|tool_call|>
        call:write_file{"path": "test.txt", "content": "hello"}
        <|tool_call|>
        call:read_file{"path": "test.txt"}
        <tool_call|>
        """#
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 2)
        XCTAssertEqual(toolCalls?.first?.name, "write")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "test.txt")
        XCTAssertEqual(toolCalls?.last?.name, "read")
    }

    // MARK: - JSON Tool Calls

    func testDecodesSingleJSONToolCall() {
        let json = """
        {"id":"call_1","function":{"name":"read_file","arguments":"{\\"path\\":\\"/tmp/test.txt\\"}"}}
        """
        let toolCalls = parser.decodeAll(from: json)
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "read")
        guard let args = toolCalls?.first?.arguments as? [String: String] else {
            XCTFail("Expected [String: String] arguments"); return
        }
        XCTAssertEqual(args["path"], "/tmp/test.txt")
    }

    func testDecodesJSONEnvelope() {
        let json = """
        {"tool_calls":[{"id":"call_1","function":{"name":"read_file","arguments":"{\\"path\\":\\"/tmp/a.txt\\"}"}},{"id":"call_2","function":{"name":"write_file","arguments":"{\\"path\\":\\"/tmp/b.txt\\"}"}}]}
        """
        let toolCalls = parser.decodeAll(from: json)
        XCTAssertEqual(toolCalls?.count, 2)
        XCTAssertEqual(toolCalls?.first?.name, "read")
        XCTAssertEqual(toolCalls?.last?.name, "write")
    }

    func testDecodesFencedJSONBlock() {
        let content = """
        Let me read the file:
        ```json
        {"id":"call_1","function":{"name":"read_file","arguments":"{\\"path\\":\\"/tmp/fenced.txt\\"}"}}
        ```
        """
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "read")
    }

    // MARK: - Name Normalization

    func testNormalizesToolNames() {
        XCTAssertEqual(ParserHelper.normalizeName("list_directory"), "ls")
        XCTAssertEqual(ParserHelper.normalizeName("list_dir"), "ls")
        XCTAssertEqual(ParserHelper.normalizeName("cli-mcp-server_run_command"), "bash")
        XCTAssertEqual(ParserHelper.normalizeName("create_file"), "write")
        XCTAssertEqual(ParserHelper.normalizeName("edit_file"), "edit")
        XCTAssertEqual(ParserHelper.normalizeName("view_file"), "read")
        XCTAssertEqual(ParserHelper.normalizeName("grep_search"), "search")
        XCTAssertEqual(ParserHelper.normalizeName("web_fetch"), "web_fetch")
        XCTAssertEqual(ParserHelper.normalizeName("internet_search"), "web_search")
        XCTAssertEqual(ParserHelper.normalizeName("apply_diff"), "edit")
        XCTAssertEqual(ParserHelper.normalizeName("run_shell"), "bash")
        XCTAssertEqual(ParserHelper.normalizeName("unknown_tool"), "unknown_tool")
    }

    // MARK: - HTML Entity Decoding

    func testDecodesHTMLEntities() {
        XCTAssertEqual(ParserHelper.decodeHTMLEntities("&quot;hello&quot;"), "\"hello\"")
        XCTAssertEqual(ParserHelper.decodeHTMLEntities("&apos;test&apos;"), "'test'")
        XCTAssertEqual(ParserHelper.decodeHTMLEntities("a &lt; b &gt; c"), "a < b > c")
        XCTAssertEqual(ParserHelper.decodeHTMLEntities("&amp;"), "&")
    }

    // MARK: - Strip Markup

    func testStripMarkup() {
        let content = """
        I'll create the file now.
        <tool_call>
        <tool name="write_file"><arg name="path">/tmp/test.txt</arg><arg name="content">hello</arg></tool>
        </tool_call>
        """
        let stripped = ToolCallFallbackParser.stripMarkup(from: content)
        XCTAssertFalse(stripped.contains("<tool_call>"))
        XCTAssertFalse(stripped.contains("<tool name="))
        XCTAssertFalse(stripped.contains("<arg name="))
    }

    // MARK: - Edge Cases

    func testReturnsNilForEmptyContent() {
        let result = parser.decodeAll(from: "")
        XCTAssertNil(result)
    }

    func testReturnsNilForPlainText() {
        let result = parser.decodeAll(from: "Hello, this is a regular response.")
        XCTAssertNil(result)
    }

    func testReturnsNilForUnclosedToolTags() {
        let result = parser.decodeAll(from: "<tool_call><tool name=\"test\">")
        XCTAssertNil(result)
    }

    // MARK: - Tool Call Content Block

    func testDecodesToolCallBlockContent() {
        let content = """
        <tool_call>
        /tmp/project/newfile.txt
        This is the file content
        </tool_call>
        """
        let toolCalls = parser.decodeAll(from: content)
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "write")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "/tmp/project/newfile.txt")
    }
}
