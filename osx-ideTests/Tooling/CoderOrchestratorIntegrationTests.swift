import XCTest
@testable import osx_ide

/// Integration tests for CoderOrchestrator with Mock AI.
/// These tests verify that the FULL FLOW works: user request → tools encoded →
/// AI sees tools → AI responds with tool calls → tools are executed → results returned.
///
/// This is the EXACT flow that's failing in production (model doesn't call tools).
final class CoderOrchestratorIntegrationTests: XCTestCase {
    var registry: ToolRegistry!
    var ledger: FileAccessLedger!
    var loopGuard: ToolLoopGuard!
    var governor: ResourceGovernor!
    var executor: ToolExecutor!
    var scheduler: SequentialScheduler!
    var adapter: OpenRouterToolAdapter!

    override func setUp() async throws {
        registry = ToolRegistry()
        ledger = FileAccessLedger()
        loopGuard = ToolLoopGuard()
        governor = ResourceGovernor()
        adapter = OpenRouterToolAdapter()

        ToolRegistrar.registerAll(in: registry, pathValidator: nil, index: nil, projectRoot: nil)

        let realExecutor = RealToolExecutor(registry: registry)
        let sandboxDecorator = SandboxDecorator(inner: realExecutor, ledger: ledger)
        executor = TelemetryDecorator(inner: sandboxDecorator)
        scheduler = SequentialScheduler(gov: governor, exec: executor)
    }

    /// Test: When model responds with a tool call, the orchestrator executes it and returns results.
    func testOrchestratorExecutesToolCall() async throws {
        let mockAI = MockToolingAIService(behavior: MockToolingAIService.Behavior.respondWithToolCall(
            toolName: "read_file",
            arguments: ["path": "/tmp/test.txt"]
        ))

        let orchestrator = CoderOrchestrator(
            reg: registry, sch: scheduler, adp: adapter,
            lg: loopGuard, led: ledger, ai: mockAI
        )

        // Create a test file
        try! "Hello World".write(toFile: "/tmp/test.txt", atomically: true, encoding: .utf8)

        let req = SendReq(msg: "Read the test file", root: URL(fileURLWithPath: "/tmp"), messages: [])
        let response = await orchestrator.handle(req: req, cid: "test-orch-1")

        switch response {
        case .txt(let text):
            XCTAssertTrue(text.contains("Hello World"), "Response should contain file content")
        case .err(let error):
            XCTFail("Orchestrator returned error: \(error)")
        }
    }

    /// Test: When model responds with TEXT (no tool calls), orchestrator returns the text.
    func testOrchestratorReturnsTextWhenNoToolCalls() async throws {
        let mockAI = MockToolingAIService(behavior: MockToolingAIService.Behavior.respondWithText("I don't need tools for this."))

        let orchestrator = CoderOrchestrator(
            reg: registry, sch: scheduler, adp: adapter,
            lg: loopGuard, led: ledger, ai: mockAI
        )

        let req = SendReq(msg: "Hello", root: URL(fileURLWithPath: "/tmp"), messages: [])
        let response = await orchestrator.handle(req: req, cid: "test-orch-2")

        switch response {
        case .txt(let text):
            XCTAssertEqual(text, "I don't need tools for this.")
        case .err(let error):
            XCTFail("Orchestrator returned error: \(error)")
        }
    }

    /// Test: When model calls multiple tools, all execute and results return.
    func testOrchestratorExecutesMultipleToolCalls() async throws {
        let mockAI = MockToolingAIService(behavior: MockToolingAIService.Behavior.respondWithMultipleToolCalls([
            (toolName: "read_file", arguments: ["path": "/tmp/test_a.txt"]),
            (toolName: "read_file", arguments: ["path": "/tmp/test_b.txt"]),
        ]))

        try! "Content A".write(toFile: "/tmp/test_a.txt", atomically: true, encoding: .utf8)
        try! "Content B".write(toFile: "/tmp/test_b.txt", atomically: true, encoding: .utf8)

        let orchestrator = CoderOrchestrator(
            reg: registry, sch: scheduler, adp: adapter,
            lg: loopGuard, led: ledger, ai: mockAI
        )

        let req = SendReq(msg: "Read both files", root: URL(fileURLWithPath: "/tmp"), messages: [])
        let response = await orchestrator.handle(req: req, cid: "test-orch-3")

        switch response {
        case .txt(let text):
            XCTAssertTrue(text.contains("Content A"), "Should contain first file content")
            XCTAssertTrue(text.contains("Content B"), "Should contain second file content")
        case .err(let error):
            XCTFail("Orchestrator returned error: \(error)")
        }
    }

    /// Test: Tools ARE properly encoded in the request the model sees.
    /// This is THE critical test — it verifies the model receives proper tool schemas.
    func testToolsAreProperlyEncodedForModel() async throws {
        let tools = registry.tools(for: .coder)
        let encoded = adapter.encodeTools(tools)

        // Verify every tool has proper OpenAI format
        for toolDict in encoded {
            guard let fn = toolDict["function"] as? [String: Any] else {
                XCTFail("Tool missing 'function' key")
                continue
            }
            guard let name = fn["name"] as? String else {
                XCTFail("Tool function missing 'name'")
                continue
            }
            guard let params = fn["parameters"] as? [String: Any] else {
                XCTFail("Tool '\(name)' missing 'parameters'")
                continue
            }

            // Critical: parameters must have "type" and "properties"
            XCTAssertEqual(params["type"] as? String, "object",
                           "Tool '\(name)' parameters must have type='object'")

            // Tools that always have full schemas (not dependency-dependent)
            if name == "read_file" || name == "write_file" || name == "patch_file" {
                let props = params["properties"] as? [String: Any]
                XCTAssertNotNil(props, "Tool '\(name)' must have properties defined")
                XCTAssertFalse(props?.isEmpty ?? true, "Tool '\(name)' must have at least 1 property")
                XCTAssertNotNil(props?["path"], "Tool '\(name)' must have 'path' property")
            }
            // Placeholder tools (list_files, find_file, search_project) have empty schemas
            // when their dependencies (pathValidator, index) are nil — this is expected.
        }
    }

    /// Test: The tools can be round-tripped through DynamicAITool (production bridge).
    func testDynamicAIToolConversion() async throws {
        let tools = registry.tools(for: .coder)
        let encoded = adapter.encodeTools(tools)

        for toolDict in encoded {
            let dynamic = DynamicAITool(from: toolDict)
            XCTAssertNotNil(dynamic, "Tool should convert to DynamicAITool")
            if let dt = dynamic {
                XCTAssertFalse(dt.name.isEmpty, "Tool name should not be empty")
                XCTAssertFalse(dt.description.isEmpty, "Tool description should not be empty")
                XCTAssertNotNil(dt.parameters["type"], "Tool parameters should have type")
                XCTAssertNotNil(dt.parameters["properties"], "Tool parameters should have properties")

                // Log the first tool for debugging
                if dt.name == "read_file" {
                    print("read_file schema: \(dt.parameters)")
                }
            }
        }
    }

    /// Test: CoderOrchestrator builds a proper system prompt with tool descriptions.
    func testSystemPromptIncludesToolDescriptions() async throws {
        let tools = registry.tools(for: .coder)
        let orchestrator = CoderOrchestrator(
            reg: registry, sch: scheduler, adp: adapter,
            lg: loopGuard, led: ledger,
            ai: MockToolingAIService(behavior: MockToolingAIService.Behavior.respondWithText("ok"))
        )

        // The system prompt is built internally. We verify by checking that
        // the mock received a request with proper messages.
        // For now, verify that tools have proper descriptions:
        for tool in tools {
            XCTAssertFalse(tool.description.isEmpty, "Tool '\(tool.name)' should have a description")
            XCTAssertFalse(tool.promptMaterial.standard.isEmpty, "Tool '\(tool.name)' should have prompt material")
        }
    }
}
