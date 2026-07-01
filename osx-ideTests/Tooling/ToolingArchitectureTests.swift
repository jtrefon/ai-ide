import XCTest
@testable import osx_ide

/// Tests for the Phase 1 tooling architecture.
/// These tests run WITHOUT the UI or app — just the core types and execution chain.
/// Feedback loop: ~2 seconds per test instead of ~30 minutes per manual session.
final class ToolingArchitectureTests: XCTestCase {
    var harness: ToolingTestHarness!

    override func setUp() async throws {
        harness = await ToolingTestHarness()
    }

    override func tearDown() async throws {
        harness = nil
    }

    /// Test that a tool can be looked up and executed through the full decorator chain.
    func testToolExecution() async throws {
        let result = await harness.testToolExecution()
        XCTAssertTrue(result.passed, result.summary)
    }

    /// Test that the sandbox blocks writes to existing files without a prior read.
    func testSandboxBlocksWriteWithoutRead() async throws {
        let result = await harness.testSandboxBlocksWriteWithoutRead()
        XCTAssertTrue(result.passed, result.summary)
    }

    /// Test that the sandbox allows writes after a prior read.
    func testSandboxAllowsWriteAfterRead() async throws {
        let result = await harness.testSandboxAllowsWriteAfterRead()
        XCTAssertTrue(result.passed, result.summary)
    }

    /// Test that the loop guard detects repeated tool calls and aborts.
    func testLoopGuard() async throws {
        let result = await harness.testLoopGuard()
        XCTAssertTrue(result.passed, result.summary)
    }

    /// Test that the registry returns the right tools for Coder mode.
    func testRegistryQueries() async throws {
        let result = await harness.testRegistryQueries()
        XCTAssertTrue(result.passed, result.summary)
    }

    /// Test the full execution chain: scheduler → decorator chain → executor → feedback.
    func testFullChain() async throws {
        let result = await harness.testFullChain()
        XCTAssertTrue(result.passed, result.summary)
    }

    /// Test that tools have proper JSON schemas (not empty).
    func testToolSchemasHaveParameters() async throws {
        let tools = await harness.registry.tools(for: .coder)
        for tool in tools {
            let dict = await task { tool.parameters.toDict() }
            XCTAssertFalse(dict.isEmpty, "Tool '\(tool.name)' has empty parameter schema")
            if let type = dict["type"] as? String {
                XCTAssertEqual(type, "object")
            }
            if tool.name == "read_file" {
                let props = dict["properties"] as? [String: Any]
                XCTAssertNotNil(props, "read_file should have properties")
                XCTAssertNotNil(props?["path"], "read_file should have 'path' property")
            }
        }
    }

    /// Test that tools are properly excluded from Coder mode.
    func testCoderModeExcludesReplaceInFile() async throws {
        let tools = await harness.registry.tools(for: .coder)
        let names = Set(tools.map { $0.name })
        XCTAssertFalse(names.contains("replace_in_file"), "Coder mode should NOT include replace_in_file")
        XCTAssertTrue(names.contains("patch_file"), "Coder mode SHOULD include patch_file")
    }

    /// Test that the adapter produces valid OpenAI-format tool schemas.
    func testAdapterProducesValidToolSchemas() async throws {
        let tools = await harness.registry.tools(for: .coder)
        let encoded = harness.adapter.encodeTools(tools)

        XCTAssertFalse(encoded.isEmpty, "Should encode at least 1 tool")

        for toolDict in encoded {
            XCTAssertEqual(toolDict["type"] as? String, "function")
            let fn = toolDict["function"] as? [String: Any]
            XCTAssertNotNil(fn, "Each tool should have a 'function' key")
            XCTAssertNotNil(fn?["name"] as? String, "Function should have a name")
            XCTAssertNotNil(fn?["description"] as? String, "Function should have a description")

            let params = fn?["parameters"] as? [String: Any]
            XCTAssertNotNil(params, "Function should have parameters")
            XCTAssertNotNil(params?["type"], "Parameters should have a type")

            // Real tools (read_file, write_file, patch_file) have properties.
            // Placeholder tools (index_*, web_*) may have empty properties — this is expected
            // until their implementations are completed.
            if let name = fn?["name"] as? String,
               ["read_file", "write_file", "patch_file"].contains(name),
               let props = params?["properties"] as? [String: Any] {
                XCTAssertFalse(props.isEmpty, "Real tool '\(name)' should have at least 1 property")
            }
        }
    }

    /// DISABLED: End-to-end test with real AI service.
    /// Enable this only when you want to test against the actual AI API.
    /// This will make real API calls and consume tokens.
    func _testEndToEndWithRealAI() async throws {
        // This would call the real AIService through the CoderOrchestrator
        // and verify tools are called correctly
        throw XCTSkip("Real AI test — enable manually")
    }
}

/// Helper to run sync code in async context
func task<T>(_ block: @Sendable @escaping () -> T) async -> T {
    return block()
}
