import XCTest
@testable import osx_ide

/// Tests that call PRODUCTION code through real execution paths.
/// Never reimplements tool logic — assembles production components, calls them, verifies output.
///
/// Rule: If the harness needs to implement tool logic, it's wrong.
///       The logic should already exist in production code. Call it.
final class ProductionToolHarness: XCTestCase {
    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("tool-harness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - PatchFileToolAdapter (production AITool bridge)

    func testPatchFileToolViaProductionAdapter() async throws {
        let testFile = tmpDir.appendingPathComponent("test.swift")
        try "let x = 1\nlet y = 2\nlet z = 3".write(to: testFile, atomically: true, encoding: .utf8)

        let adapter = PatchFileToolAdapter()
        XCTAssertEqual(adapter.name, "patch_file")
        XCTAssertTrue(adapter.description.contains("line range"))

        let result = try await adapter.execute(arguments: ToolArguments([
            "path": testFile.path,
            "start_line": 2,
            "end_line": 2,
            "new_content": "let y = 42"
        ]))

        // Verify structured feedback envelope from production ToolFeedbackFormatter
        XCTAssertTrue(result.contains("status: success"), "Should contain status line")
        XCTAssertTrue(result.contains("content:"), "Should contain content section")
        XCTAssertTrue(result.contains("+let y = 42"), "Should show new content")
        XCTAssertTrue(result.contains("-let y = 2"), "Should show old content")

        // Verify file was actually modified
        let content = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(content, "let x = 1\nlet y = 42\nlet z = 3")
    }

    func testPatchFileToolFileNotFound() async throws {
        // Adapter returns formatted feedback (doesn't throw) — error envelope in the string
        let adapter = PatchFileToolAdapter()
        let result = try await adapter.execute(arguments: ToolArguments([
            "path": "/nonexistent/path.txt",
            "start_line": 1,
            "end_line": 1,
            "new_content": "test"
        ]))
        // The error envelope should be in the returned string
        XCTAssertTrue(result.contains("FILE_NOT_FOUND") || result.contains("not found"),
                      "Result should contain error info: \(result)")
    }

    // MARK: - ToolFeedbackFormatter (production formatting)

    func testToolFeedbackSuccessEnvelope() {
        let formatter = ToolFeedbackFormatter()
        let fb = ToolFeedback.success("File read successfully", text: "file content here")
        let output = formatter.format(fb)
        XCTAssertTrue(output.contains("status: success"))
        XCTAssertTrue(output.contains("message: File read successfully"))
        XCTAssertTrue(output.contains("content:"))
        XCTAssertTrue(output.contains("file content here"))
    }

    func testToolFeedbackErrorEnvelope() {
        let formatter = ToolFeedbackFormatter()
        let fb = ToolFeedback.error("File not found", code: "FILE_NOT_FOUND",
            alts: [ToolAlternative(desc: "Search for the file", tool: "search_project", args: ["query": "test"])])
        let output = formatter.format(fb)
        XCTAssertTrue(output.contains("status: error"))
        XCTAssertTrue(output.contains("error_code: FILE_NOT_FOUND"))
        XCTAssertTrue(output.contains("recoverable: true"))
        XCTAssertTrue(output.contains("search_project"))
    }

    func testToolFeedbackBatchEnvelope() {
        let formatter = ToolFeedbackFormatter()
        let results = [
            ToolFeedback.success("Read file A", text: "content A"),
            ToolFeedback.success("Read file B", text: "content B"),
        ]
        let output = formatter.formatBatch(results)
        XCTAssertTrue(output.contains("result_1:"))
        XCTAssertTrue(output.contains("result_2:"))
        XCTAssertTrue(output.contains("content A"))
        XCTAssertTrue(output.contains("content B"))
    }

    // MARK: - AIMode Tool Filtering

    func testCoderModeExcludesReplaceInFile() {
        // Create minimal AITool stubs (NOT reimplementing tool logic)
        let readTool = SimpleTool(name: "read_file")
        let patchTool = SimpleTool(name: "patch_file")
        let replaceTool = SimpleTool(name: "replace_in_file")

        let coderTools = AIMode.coder.allowedTools(from: [readTool, patchTool, replaceTool])
        let names = Set(coderTools.map { $0.name })

        XCTAssertTrue(names.contains("read_file"))
        XCTAssertTrue(names.contains("patch_file"))
        XCTAssertFalse(names.contains("replace_in_file"))
    }

    func testChatModeExcludesAllTools() {
        let tools = [SimpleTool(name: "read_file"), SimpleTool(name: "write_file")]
        let chatTools = AIMode.chat.allowedTools(from: tools)
        XCTAssertTrue(chatTools.isEmpty)
    }

    func testAgentModeIncludesAllTools() {
        let tools = [SimpleTool(name: "read_file"), SimpleTool(name: "replace_in_file")]
        let agentTools = AIMode.agent.allowedTools(from: tools)
        XCTAssertEqual(agentTools.count, 2)
    }
}

// MARK: - Minimal AITool stub for testing mode filtering
// This is NOT implementing tool logic — it's providing a minimal AITool
// that conforms to the protocol so we can test AIMode.allowedTools().
// The execute method throws because it should never be called.
private struct SimpleTool: AITool, @unchecked Sendable {
    let name: String
    let description = "Test tool"
    var parameters: [String: Any] { ["type": "object", "properties": [:]] }

    func execute(arguments: ToolArguments) async throws -> String {
        throw AppError.aiServiceError("SimpleTool should not be executed from tests")
    }
}
