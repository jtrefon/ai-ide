import XCTest
@testable import osx_ide

/// Tests the real Coder mode flow end-to-end through production code paths.
/// No tool logic reimplementation. Uses production AITool instances,
/// production AIMode filtering, and production ToolFeedbackFormatter.
///
/// Dependencies that require app-level setup (PathValidator, EventBus) are
/// provided by the existing osx-ideHarnessTests target. Here we test the
/// components that are directly constructable without app bootstrap.
final class CoderModeIntegrationTest: XCTestCase {
    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("coder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Complex Scenario 1: Full patch_file workflow

    /// Tests the complete read-patch-verify cycle using production PatchFileToolAdapter.
    /// This is the most common agent workflow: read file → edit → verify.
    func testReadPatchVerifyCycle() async throws {
        let testFile = tmpDir.appendingPathComponent("main.swift")
        try """
        func greet(name: String) {
            print("Hello, \(name)")
        }
        greet(name: "World")
        """.write(to: testFile, atomically: true, encoding: .utf8)

        let adapter = PatchFileToolAdapter()

        // Step 1: Patch — change "World" to "Swift"
        let result = try await adapter.execute(arguments: ToolArguments([
            "path": testFile.path,
            "start_line": 4,
            "end_line": 4,
            "new_content": "greet(name: \"Swift\")"
        ]))

        // Verify structured feedback envelope
        XCTAssertTrue(result.contains("status: success"), "Should have status: success")
        XCTAssertTrue(result.contains("content:"), "Should have content section")
        XCTAssertTrue(result.contains("-greet(name: \"World\")"), "Should show old line")
        XCTAssertTrue(result.contains("+greet(name: \"Swift\")"), "Should show new line")

        // Verify file actually changed
        let content = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertTrue(content.contains("greet(name: \"Swift\")"), "File should have updated content")
        XCTAssertFalse(content.contains("greet(name: \"World\")"), "File should not have old content")

        // Step 2: Patch again — insert a new line
        let result2 = try await adapter.execute(arguments: ToolArguments([
            "path": testFile.path,
            "start_line": 2,
            "end_line": 2,
            "new_content": "    print(\"Debug: greet called with \\(name)\")"
        ]))

        XCTAssertTrue(result2.contains("status: success"), "Second patch should succeed")
        let content2 = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertTrue(content2.contains("Debug: greet called"), "Should have debug line")
    }

    // MARK: - Complex Scenario 2: Multi-line edit

    /// Tests patching a range of multiple lines — replacing a whole function body.
    func testMultiLinePatch() async throws {
        let testFile = tmpDir.appendingPathComponent("math.swift")
        try """
        func add(a: Int, b: Int) -> Int {
            return a + b
        }
        """.write(to: testFile, atomically: true, encoding: .utf8)

        let adapter = PatchFileToolAdapter()

        // Replace the function body entirely
        let result = try await adapter.execute(arguments: ToolArguments([
            "path": testFile.path,
            "start_line": 2,
            "end_line": 2,
            "new_content": "    let result = a + b\n    print(\"add: \\(a) + \\(b) = \\(result)\")\n    return result"
        ]))

        XCTAssertTrue(result.contains("status: success"), "Multi-line edit should succeed")
        let content = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertTrue(content.contains("print(\"add:"), "Should have new print line")
    }

    // MARK: - Complex Scenario 3: Error feedback

    /// Tests that errors return structured feedback, not crashes.
    func testErrorFeedbackEnvelope() async throws {
        let adapter = PatchFileToolAdapter()

        // Test 1: Missing file
        let result1 = try await adapter.execute(arguments: ToolArguments([
            "path": tmpDir.appendingPathComponent("nonexistent.swift").path,
            "start_line": 1,
            "end_line": 1,
            "new_content": "test"
        ]))
        XCTAssertTrue(result1.contains("FILE_NOT_FOUND") || result1.contains("not found"),
                      "Missing file should return error info. Got: \(result1.prefix(100))")

        // Test 2: Invalid line range
        let testFile = tmpDir.appendingPathComponent("short.txt")
        try "only one line".write(to: testFile, atomically: true, encoding: .utf8)

        let result2 = try await adapter.execute(arguments: ToolArguments([
            "path": testFile.path,
            "start_line": 10,
            "end_line": 10,
            "new_content": "test"
        ]))
        XCTAssertTrue(result2.contains("INVALID_LINE_RANGE") || result2.contains("Invalid"),
                      "Bad line range should return error info. Got: \(result2.prefix(100))")
    }

    // MARK: - Complex Scenario 4: Coder mode tool composition

    /// Tests that the production tool provider + mode filtering produces
    /// the correct tool set for Coder mode.
    func testCoderModeToolComposition() throws {
        // Build minimal tools — testing AIMode.coder.allowedTools() production path
        let readTool = SimpleAITool(name: "read_file")
        let writeTool = SimpleAITool(name: "write_file")
        let patchTool = SimpleAITool(name: "patch_file")
        let replaceTool = SimpleAITool(name: "replace_in_file")
        let searchTool = SimpleAITool(name: "search_project")
        let terminalTool = SimpleAITool(name: "run_command")
        let chatTool = SimpleAITool(name: "chat")

        let allTools: [AITool] = [readTool, writeTool, patchTool, replaceTool, searchTool, terminalTool, chatTool]

        // Coder mode filtering
        let coderTools = AIMode.coder.allowedTools(from: allTools)
        let names = Set(coderTools.map { $0.name })

        XCTAssertTrue(names.contains("read_file"), "Coder needs read_file")
        XCTAssertTrue(names.contains("write_file"), "Coder needs write_file")
        XCTAssertTrue(names.contains("patch_file"), "Coder needs patch_file")
        XCTAssertTrue(names.contains("run_command"), "Coder needs terminal access")
        XCTAssertFalse(names.contains("replace_in_file"), "Coder excludes replace_in_file")

        // Agent mode (full access)
        let agentTools = AIMode.agent.allowedTools(from: allTools)
        XCTAssertEqual(agentTools.count, 7, "Agent mode should have all tools")

        // Chat mode (no tools)
        let chatTools = AIMode.chat.allowedTools(from: allTools)
        XCTAssertTrue(chatTools.isEmpty, "Chat mode should have no tools")
    }

    // MARK: - Complex Scenario 5: Multiple tool feedback format

    /// Tests the ToolFeedbackFormatter with realistic batch results
    /// mimicking what the ToolLoopHandler would produce.
    func testRealisticBatchFeedback() {
        let formatter = ToolFeedbackFormatter()

        let results: [ToolFeedback] = [
            .success("Read main.swift (245 bytes)", text: "import Foundation\n\nfunc main() {\n    print(\"hello\")\n}\n",
                     meta: ["path": "main.swift", "byteCount": "245"]),
            .success("Patched main.swift lines 3-3", text: "--- a (lines 3-3)\n-    print(\"hello\")\n+    print(\"hello world\")\n",
                     meta: ["path": "main.swift", "verified": "true"]),
            .success("Command completed (exit 0)", text: "Build Succeeded",
                     meta: ["exitCode": "0", "duration": "2.3s"]),
        ]

        let output = formatter.formatBatch(results)
        XCTAssertTrue(output.contains("result_1:"), "Should have first result")
        XCTAssertTrue(output.contains("result_2:"), "Should have second result")
        XCTAssertTrue(output.contains("result_3:"), "Should have third result")
        XCTAssertTrue(output.contains("import Foundation"), "Should include read content")
        XCTAssertTrue(output.contains("+    print(\"hello world\")"), "Should include diff")
        XCTAssertTrue(output.contains("Build Succeeded"), "Should include command output")
        XCTAssertTrue(output.contains("path: main.swift"), "Should include metadata")
        XCTAssertTrue(output.contains("verified: true"), "Should include verification status")
    }
}

// MARK: - Minimal AITool for testing mode filtering
// NOT implementing tool logic — just providing protocol conformance
// so we can test production AIMode.allowedTools() path
private struct SimpleAITool: AITool, @unchecked Sendable {
    let name: String
    let description = "Test tool"
    var parameters: [String: Any] { ["type": "object", "properties": [:]] }

    func execute(arguments: ToolArguments) async throws -> String {
        throw AppError.aiServiceError("SimpleTool should not be executed from tests")
    }
}
