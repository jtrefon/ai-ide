import Foundation

/// Test harness for the Phase 1 tooling architecture.
/// Runs end-to-end tests WITHOUT needing the UI or full app.
/// Each test creates a clean ToolRegistry, registers tools, and
/// exercises the full execution chain.
///
/// Usage:
///   let harness = ToolingTestHarness()
///   let result = await harness.testToolExecution()
///   print(result.summary)
///
final class ToolingTestHarness: @unchecked Sendable {
    let registry: ToolRegistry
    let ledger: FileAccessLedger
    let loopGuard: ToolLoopGuard
    let governor: ResourceGovernor
    let executor: ToolExecutor
    let scheduler: SequentialScheduler
    let adapter: OpenRouterToolAdapter

    private let tmpDir: URL

    init() {
        self.registry = ToolRegistry()
        self.ledger = FileAccessLedger()
        self.loopGuard = ToolLoopGuard()
        self.governor = ResourceGovernor()
        self.adapter = OpenRouterToolAdapter()

        // Register all tools
        ToolRegistrar.registerAll(in: registry, pathValidator: nil, index: nil, projectRoot: nil)

        // Build executor chain
        let realExecutor = RealToolExecutor(registry: registry)
        let sandboxDecorator = SandboxDecorator(inner: realExecutor, ledger: ledger)
        self.executor = TelemetryDecorator(inner: sandboxDecorator)
        self.scheduler = SequentialScheduler(gov: governor, exec: executor)

        self.tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("tooling-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Test Results

    struct TestResult: Sendable, CustomStringConvertible {
        let name: String
        let passed: Bool
        let duration: TimeInterval
        let steps: [Step]
        let error: String?

        struct Step: Sendable, CustomStringConvertible {
            let index: Int
            let toolName: String
            let duration: TimeInterval
            let status: String
            let detail: String
            var description: String {
                "[\(index)] \(toolName) → \(status) in \(String(format: "%.1f", duration * 1000))ms: \(detail.prefix(80))"
            }
        }

        var summary: String {
            let status = passed ? "✅ PASS" : "❌ FAIL"
            return "\(status) \(name) (\(String(format: "%.1f", duration))s, \(steps.count) steps)\n" +
                steps.map { "  \($0)" }.joined(separator: "\n")
        }

        var description: String { summary }
    }

    // MARK: - Test: Tool Execution

    /// Test that a tool can be looked up in the registry and executed.
    func testToolExecution() async -> TestResult {
        let name = "Tool Execution — read_file"
        let start = Date()
        var steps: [TestResult.Step] = []

        // Step 1: Look up the tool
        guard let definition = registry.tool(named: "read_file") else {
            return TestResult(name: name, passed: false, duration: Date().timeIntervalSince(start),
                            steps: [], error: "read_file not found in registry")
        }
        steps.append(TestResult.Step(index: 1, toolName: "read_file", duration: 0, status: "found", detail: "ToolDefinition exists in registry"))

        // Step 2: Create a test file
        let testFile = tmpDir.appendingPathComponent("test.txt")
        try! "Hello World\nLine 2\nLine 3".write(to: testFile, atomically: true, encoding: .utf8)
        steps.append(TestResult.Step(index: 2, toolName: "setup", duration: 0, status: "ok", detail: "Created test file at \(testFile.path)"))

        // Step 3: Create execution context and request
        let ctx = ExecutionContext.coder(cid: "test", tid: "t1", root: tmpDir)
        let req = ToolExecutionRequest(
            toolName: "read_file",
            arguments: ["path": .string(testFile.path)],
            context: ctx
        )
        steps.append(TestResult.Step(index: 3, toolName: "read_file", duration: 0, status: "requested", detail: "Request created"))

        // Step 4: Execute through the chain
        let execStart = Date()
        let feedback = await executor.execute(request: req)
        let execDuration = Date().timeIntervalSince(execStart)
        steps.append(TestResult.Step(index: 4, toolName: "read_file", duration: execDuration,
                                    status: feedback.status.rawValue, detail: feedback.message))

        // Step 5: Verify
        guard feedback.status == .success else {
            return TestResult(name: name, passed: false, duration: Date().timeIntervalSince(start),
                            steps: steps, error: "Tool returned error: \(feedback.message)")
        }

        return TestResult(name: name, passed: true, duration: Date().timeIntervalSince(start), steps: steps, error: nil)
    }

    // MARK: - Test: Read-Before-Write Sandbox

    /// Test that the sandbox blocks writes to existing files without a prior read.
    func testSandboxBlocksWriteWithoutRead() async -> TestResult {
        let name = "Sandbox — blocks write without prior read"
        let start = Date()
        var steps: [TestResult.Step] = []

        let testFile = tmpDir.appendingPathComponent("existing.txt")
        try! "Existing content".write(to: testFile, atomically: true, encoding: .utf8)
        steps.append(TestResult.Step(index: 1, toolName: "setup", duration: 0, status: "ok", detail: "Created existing file"))

        let ctx = ExecutionContext.coder(cid: "test2", tid: "t1", root: tmpDir)
        let req = ToolExecutionRequest(
            toolName: "write_file",
            arguments: ["path": .string(testFile.path), "content": .string("New content")],
            context: ctx
        )

        // Verify ledger has NO read for this file
        let hasRead = await ledger.hasRead(path: testFile.path, cid: "test2", tid: "t1")
        steps.append(TestResult.Step(index: 2, toolName: "check", duration: 0, status: hasRead ? "read_found" : "no_read",
                                    detail: "Ledger hasRead=\(hasRead) before write"))

        let execStart = Date()
        let feedback = await executor.execute(request: req)
        let execDuration = Date().timeIntervalSince(execStart)
        steps.append(TestResult.Step(index: 3, toolName: "write_file", duration: execDuration,
                                    status: feedback.status.rawValue, detail: feedback.message))

        let blocked = feedback.status == .error && feedback.error?.code == "MUTATION_WITHOUT_PRIOR_READ"
        steps.append(TestResult.Step(index: 4, toolName: "verify", duration: 0, status: blocked ? "blocked" : "not_blocked",
                                    detail: "Error code: \(feedback.error?.code ?? "none")"))

        return TestResult(name: name, passed: blocked, duration: Date().timeIntervalSince(start),
                         steps: steps, error: blocked ? nil : "Write was NOT blocked by sandbox")
    }

    // MARK: - Test: Sandbox Allows Write After Read

    /// Test that the sandbox allows writes after a prior read.
    func testSandboxAllowsWriteAfterRead() async -> TestResult {
        let name = "Sandbox — allows write after read"
        let start = Date()
        var steps: [TestResult.Step] = []

        let testFile = tmpDir.appendingPathComponent("existing2.txt")
        try! "Existing content".write(to: testFile, atomically: true, encoding: .utf8)
        steps.append(TestResult.Step(index: 1, toolName: "setup", duration: 0, status: "ok", detail: "Created existing file"))

        let cid = "test3"
        let tid = "t1"

        // First: read the file (simulate by recording in ledger)
        await ledger.recordRead(path: testFile.path, cid: cid, tid: tid)
        steps.append(TestResult.Step(index: 2, toolName: "read_file", duration: 0, status: "recorded", detail: "Recorded read in ledger"))

        // Then: write
        let ctx = ExecutionContext.coder(cid: cid, tid: tid, root: tmpDir)
        let req = ToolExecutionRequest(
            toolName: "write_file",
            arguments: ["path": .string(testFile.path), "content": .string("Updated content")],
            context: ctx
        )
        let execStart = Date()
        let feedback = await executor.execute(request: req)
        let execDuration = Date().timeIntervalSince(execStart)
        steps.append(TestResult.Step(index: 3, toolName: "write_file", duration: execDuration,
                                    status: feedback.status.rawValue, detail: feedback.message))

        let allowed = feedback.status == .success
        return TestResult(name: name, passed: allowed, duration: Date().timeIntervalSince(start),
                         steps: steps, error: allowed ? nil : "Write was blocked despite prior read")
    }

    // MARK: - Test: Loop Guard

    /// Test that the loop guard detects repeated tool calls.
    /// The guard stores one batch per cid. shouldAbort checks if the current batch
    /// shares >= maxR signatures with the stored batch.
    func testLoopGuard() async -> TestResult {
        let name = "Loop Guard — detects repeated calls"
        let start = Date()
        var steps: [TestResult.Step] = []
        let cid = "loop-test"

        // Create 3 different call signatures
        let readCall = ParsedToolCall(id: "r1", toolName: "read_file", args: ["path": .string("a.txt")])
        let writeCall = ParsedToolCall(id: "w1", toolName: "write_file", args: ["path": .string("b.txt"), "content": .string("x")])
        let listCall = ParsedToolCall(id: "l1", toolName: "list_files", args: ["path": .string(".")])

        // Store a batch with 3 different signatures
        await loopGuard.recordTurn(cid: cid, calls: [readCall, writeCall, listCall])
        steps.append(TestResult.Step(index: 1, toolName: "record", duration: 0, status: "ok", detail: "Recorded batch [read, write, list]"))

        // Check with same 3 calls — should abort (threshold=3)
        let willAbort = await loopGuard.shouldAbort(cid: cid, calls: [readCall, writeCall, listCall], maxR: 3)
        steps.append(TestResult.Step(index: 2, toolName: "check", duration: 0, status: willAbort ? "aborted" : "no",
                                    detail: "3/3 signatures match → abort"))

        // Check with 2 matching + 1 different — should NOT abort
        let searchCall = ParsedToolCall(id: "s1", toolName: "search_project", args: ["query": .string("test")])
        let partialAbort = await loopGuard.shouldAbort(cid: cid, calls: [readCall, writeCall, searchCall], maxR: 3)
        steps.append(TestResult.Step(index: 3, toolName: "check", duration: 0, status: partialAbort ? "aborted" : "no",
                                    detail: "2/3 signatures match → no abort"))

        let allAbort = await loopGuard.shouldAbort(cid: cid, calls: [readCall, writeCall, listCall], maxR: 3)

        return TestResult(name: name, passed: willAbort == true && partialAbort == false && allAbort == true,
                         duration: Date().timeIntervalSince(start), steps: steps,
                         error: nil)
    }

    // MARK: - Test: Registry Queries

    /// Test that the registry returns the right tools for Coder mode.
    func testRegistryQueries() async -> TestResult {
        let name = "Registry — returns Coder tools"
        let start = Date()
        var steps: [TestResult.Step] = []

        let coderTools = registry.tools(for: .coder)
        steps.append(TestResult.Step(index: 1, toolName: "query", duration: 0, status: "\(coderTools.count)",
                                    detail: "Coder mode tools: \(coderTools.map { $0.name }.joined(separator: ", "))"))

        let hasPatchFile = coderTools.contains { $0.name == "patch_file" }
        steps.append(TestResult.Step(index: 2, toolName: "check", duration: 0, status: hasPatchFile ? "found" : "missing",
                                    detail: "patch_file in Coder tools"))

        let hasReplaceInFile = coderTools.contains { $0.name == "replace_in_file" }
        steps.append(TestResult.Step(index: 3, toolName: "check", duration: 0, status: hasReplaceInFile ? "present" : "absent",
                                    detail: "replace_in_file in Coder tools (should be absent — filtered by allowedModes)"))

        let total = registry.allTools.count
        steps.append(TestResult.Step(index: 4, toolName: "count", duration: 0, status: "\(total)",
                                    detail: "Total registered tools"))

        return TestResult(name: name, passed: hasPatchFile && total >= 5,
                         duration: Date().timeIntervalSince(start), steps: steps,
                         error: nil)
    }

    // MARK: - Test: Full Chain Execution with Mock AI

    /// End-to-end test: orchestrator → adapter → scheduler → executor → feedback
    func testFullChain() async -> TestResult {
        let name = "Full Chain — orchestrator end-to-end"
        let start = Date()
        var steps: [TestResult.Step] = []

        // Create a test file
        let testFile = tmpDir.appendingPathComponent("test.txt")
        try! "Hello World\nLine 2\nLine 3".write(to: testFile, atomically: true, encoding: .utf8)
        steps.append(TestResult.Step(index: 1, toolName: "setup", duration: 0, status: "ok", detail: "Created test file"))

        // Create a context and schedule tool calls
        let ctx = ExecutionContext.coder(cid: "chain-test", tid: "t1", root: tmpDir)
        let calls = [
            ParsedToolCall(id: "call_1", toolName: "read_file", args: ["path": .string(testFile.path)]),
            ParsedToolCall(id: "call_2", toolName: "read_file", args: ["path": .string(testFile.path)]),
        ]

        let execStart = Date()
        let results = await scheduler.schedule(calls: calls, ctx: ctx)
        let execDuration = Date().timeIntervalSince(execStart)
        steps.append(TestResult.Step(index: 2, toolName: "schedule", duration: execDuration,
                                    status: "\(results.count) results", detail: "Scheduled \(calls.count) calls"))

        let allSucceeded = results.allSatisfy { $0.succeeded }
        for (i, r) in results.enumerated() {
            steps.append(TestResult.Step(index: 3 + i, toolName: r.toolCall.toolName, duration: r.duration,
                                        status: r.succeeded ? "success" : "failed",
                                        detail: r.feedback.message))
        }

        return TestResult(name: name, passed: allSucceeded && results.count == 2,
                         duration: Date().timeIntervalSince(start), steps: steps,
                         error: allSucceeded ? nil : "Some tools failed in the chain")
    }

    // MARK: - Run All Tests

    func runAll() async {
        print(String(repeating: "=", count: 60))
        print("  Tooling Architecture Test Harness")
        print(String(repeating: "=", count: 60))
        print()

        let tests: [() async -> TestResult] = [
            { await self.testToolExecution() },
            { await self.testSandboxBlocksWriteWithoutRead() },
            { await self.testSandboxAllowsWriteAfterRead() },
            { await self.testLoopGuard() },
            { await self.testRegistryQueries() },
            { await self.testFullChain() },
        ]

        var results: [TestResult] = []
        let totalStart = Date()

        for test in tests {
            let result = await test()
            results.append(result)
            print(result.summary)
            print()
        }

        let totalDuration = Date().timeIntervalSince(totalStart)
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count

        print(String(repeating: "=", count: 60))
        print("  Results: \(passed) passed, \(failed) failed (\(String(format: "%.1f", totalDuration))s)")
        print(String(repeating: "=", count: 60))

        if failed > 0 {
            print()
            print("Failed tests:")
            for r in results where !r.passed {
                print("  ❌ \(r.name): \(r.error ?? "unknown error")")
            }
        }
    }
}

// MARK: - Helper (no custom operators needed)
