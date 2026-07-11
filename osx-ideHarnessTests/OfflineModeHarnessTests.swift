import XCTest
@testable import osx_ide

/// Dedicated offline harness tests.
/// These tests validate offline-specific behavior and should be run separately
/// from production-parity online harness suites.
@MainActor
final class OfflineModeHarnessTests: XCTestCase {
    private final class NoopErrorManager: ObservableObject, ErrorManagerProtocol {
        @Published var currentError: AppError?
        @Published var showErrorAlert: Bool = false

        func handle(_ error: AppError) {
            currentError = error
        }

        func handle(_ error: Error, context: String) {
            currentError = .unknown("\(context): \(error.localizedDescription)")
        }

        func dismissError() {
            currentError = nil
            showErrorAlert = false
        }
    }

    private var temporaryDirectories: [URL] = []
    private let maxScenarioAttempts = 2

    override func setUp() async throws {
        try await super.setUp()
        await TestConfigurationProvider.shared.setConfiguration(.isolated)
    }

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        await TestConfigurationProvider.shared.resetToDefault()
        try await super.tearDown()
    }

    func testOfflineHarnessRoutesAgentModeIntoLocalModelPath() async throws {
        let runtime = try await makeRuntime(offlineModeEnabled: true)
        let manager = runtime.manager
        manager.currentMode = .agent

        let fileName = "offline-test-\(UUID().uuidString).txt"

        manager.currentInput = "Create a file named \(fileName)"
        manager.sendMessage()

        let completedCreateFileMessage = try await waitForCompletedToolExecution(
            named: "create_file",
            in: manager,
            timeoutSeconds: 30
        )
        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 30)
        XCTAssertFalse(timedOut, "Expected offline local agent run to finish after create_file execution")

        XCTAssertTrue(
            completedCreateFileMessage.content.contains("Reserved file path at")
                || completedCreateFileMessage.content.contains(fileName),
            "Expected offline local agent run to complete create_file execution, got: \(completedCreateFileMessage.content)"
        )
        XCTAssertFalse(
            manager.error?.contains("Agent mode is unavailable in Offline Mode") ?? false,
            "Offline agent requests should reach local MLX execution instead of the old routing gate"
        )
    }

    func testOfflineHarnessCanCompleteMultiStepLocalToolFlow() async throws {
        let projectRoot = makeTempDir(prefix: "offline_multiturn")
        let sourceFile = projectRoot.appendingPathComponent("source.txt")
        try "hello offline".write(to: sourceFile, atomically: true, encoding: .utf8)

        let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        manager.currentInput = "Read source.txt and create result.txt containing exactly HELLO OFFLINE. Use the available tools and then finish."
        manager.sendMessage()

        let completedToolMessages = try await waitForCompletedToolExecutions(
            requiredToolNames: [
                ["read_file", "list_files", "index_read_file", "index_search_symbols", "index_search_text", "index_list_files"],
                ["write_file", "create_file", "write_files", "replace_in_file"]
            ],
            in: manager,
            timeoutSeconds: 60
        )
        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 60)
        XCTAssertFalse(timedOut, "Expected offline local multi-step tool flow to finish after completing required tool categories")

        let executedToolNames = completedToolMessages.compactMap(\ .toolName)
        XCTAssertTrue(
            executedToolNames.contains("read_file") || executedToolNames.contains("list_files"),
            "Expected offline local agent to inspect project state before writing. Tools: \(executedToolNames)"
        )
        XCTAssertTrue(
            executedToolNames.contains("write_file") || executedToolNames.contains("create_file"),
            "Expected offline local agent to perform a file mutation step. Tools: \(executedToolNames)"
        )
    }

    func testOfflineHarnessMinimalToolSubsetCanCreateFileThroughLocalMLX() async throws {
        let projectRoot = makeTempDir(prefix: "offline_minimal_tools")
        let container = try await makeOfflineContainer(projectRoot: projectRoot)
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot, seedGreeting: false)
        let sendCoordinator = makeMinimalSendCoordinator(
            projectRoot: projectRoot,
            container: container,
            historyCoordinator: historyCoordinator
        )
        let conversationId = historyCoordinator.currentConversationId
        let fileName = "minimal-offline-\(UUID().uuidString).txt"

        let minimalTools = makeMinimalOfflineTools(projectRoot: projectRoot, eventBus: container.eventBus)

        try await sendCoordinator.send(
            SendRequest(
                userInput: "Create a file named \(fileName) using the create_file tool, then finish.",
                mode: .agent,
                projectRoot: projectRoot,
                conversationId: conversationId,
                runId: UUID().uuidString,
                availableTools: minimalTools,
                cancelledToolCallIds: { [] },
                qaReviewEnabled: false,
                draftAssistantMessageId: nil
            )
        )

        let completedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed
        }
        let executedToolNames = completedToolMessages.compactMap(\.toolName)

        XCTAssertTrue(
            executedToolNames.contains("create_file"),
            "Expected minimal local MLX tool subset to execute create_file. Tools: \(executedToolNames)"
        )

        let listedFiles = listAllFiles(under: projectRoot)
        XCTAssertTrue(
            listedFiles.contains(fileName),
            "Expected minimal local MLX tool subset to create \(fileName). Files: \(listedFiles)"
        )
    }

    func testOfflineHarnessSimpleGreetingProducesAssistantReply() async throws {
        let runtime = try await makeRuntime(offlineModeEnabled: true)
        let manager = runtime.manager
        manager.currentMode = .chat

        manager.currentInput = "Reply with exactly one short greeting sentence and stop."
        manager.sendMessage()

        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 30)
        XCTAssertFalse(timedOut, "Expected offline local greeting run to finish")

        let completedToolExecutions = manager.messages.filter { $0.isToolExecution && $0.toolStatus == .completed }
        let completedToolNames = completedToolExecutions.compactMap(\.toolName)
        XCTAssertTrue(
            completedToolExecutions.isEmpty,
            "Expected simple greeting scenario to complete without tool executions. Tools: \(completedToolNames)"
        )

        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        let finalAssistantContent = assistantMessages
            .last?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        XCTAssertFalse(
            finalAssistantContent.isEmpty,
            "Expected offline local greeting run to produce assistant text"
        )
    }

    func testOfflineHarnessInferenceBenchmarkSimpleGreeting() async throws {
        let iterationCount = benchmarkIterationCount()
        let prompt = "Reply with exactly one short greeting sentence and stop."
        let runtime = try await makeRuntime(offlineModeEnabled: true, profile: .benchmark)
        let manager = runtime.manager
        let testId = "offline-greeting-benchmark-\(UUID().uuidString.prefix(8))"
        let inferenceConfiguration = runtime.defaultInferenceConfiguration

        await LocalModelInferenceOverrides.shared.clear()

        await InferenceMetricsCollector.shared.clearMetrics()
        await InferenceMetricsCollector.shared.startTest(testId: testId)
        defer {
            Task {
                await InferenceMetricsCollector.shared.endTest()
            }
        }

        for iteration in 1...iterationCount {
            manager.startNewConversation()
            manager.clearConversation()
            manager.currentMode = .chat
            manager.currentInput = prompt
            await LocalModelGenerationPerformanceRecorder.shared.clear()

            let turn = await InferenceMetricsCollector.shared.incrementTurn()
            var timer = InferenceTimer()
            manager.sendMessage()

            let sawFirstToken = try await waitForAssistantFirstToken(in: manager, timeoutSeconds: 60)
            XCTAssertTrue(sawFirstToken, "Expected benchmark run \(iteration) to emit assistant output")
            timer.recordFirstToken()

            let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 60)
            XCTAssertFalse(timedOut, "Expected benchmark run \(iteration) to finish")

            let finalAssistantContent = manager.messages
                .filter { $0.role == .assistant && !$0.isDraft }
                .last?
                .content
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            XCTAssertFalse(finalAssistantContent.isEmpty, "Expected benchmark run \(iteration) to produce text")

            let promptTokenCount = try await LocalModelTokenCounter.shared.tokenCount(
                text: prompt,
                modelId: runtime.modelId
            )
            let outputTokenCount = try await LocalModelTokenCounter.shared.tokenCount(
                text: finalAssistantContent,
                modelId: runtime.modelId
            )
            let performanceSnapshot = try await waitForLatestLocalPerformanceSnapshot()
            let metric = timer.finalize(
                testId: testId,
                modelId: runtime.modelId,
                inferenceConfiguration: inferenceConfiguration,
                turn: turn,
                promptTokens: promptTokenCount,
                outputTokens: outputTokenCount,
                performanceSnapshot: performanceSnapshot
            )
            await InferenceMetricsCollector.shared.recordMetrics(metric)
            print(metric.summary)
        }

        guard let aggregateStats = await InferenceMetricsCollector.shared.aggregateStats() else {
            XCTFail("Expected aggregate benchmark statistics")
            return
        }

        print(aggregateStats.summary)
        XCTAssertGreaterThan(aggregateStats.avgTokensPerSecond, 0)

        let csv = await InferenceMetricsCollector.shared.exportCSV()
        let csvURL = try saveBenchmarkCSV(csv, testId: testId)
        print("[Inference Metrics] CSV saved to \(csvURL.path)")
    }

    func testOfflineHarnessInferenceParameterSweepLongPrompt() async throws {
        let runtime = try await makeRuntime(offlineModeEnabled: true, profile: .benchmark)
        let manager = runtime.manager
        let testId = "offline-parameter-sweep-\(UUID().uuidString.prefix(8))"
        let prompt = try await makeLongBenchmarkPrompt(
            modelId: runtime.modelId,
            targetTokens: benchmarkPromptTargetTokenCount()
        )
        let promptTokenCount = try await LocalModelTokenCounter.shared.tokenCount(
            text: prompt,
            modelId: runtime.modelId
        )
        let configurations = benchmarkConfigurations(defaultConfiguration: runtime.defaultInferenceConfiguration)

        await InferenceMetricsCollector.shared.clearMetrics()
        await InferenceMetricsCollector.shared.startTest(testId: testId)
        defer {
            Task {
                await LocalModelInferenceOverrides.shared.clear()
                await InferenceMetricsCollector.shared.endTest()
            }
        }

        for configuration in configurations {
                await LocalModelInferenceOverrides.shared.set(
                    LocalModelInferenceOverrides(
                        contextLength: configuration.contextLength,
                        maxKVSize: configuration.maxKVSize,
                        maxOutputTokens: configuration.maxOutputTokens,
                        prefillStepSize: configuration.prefillStepSize,
                        temperature: configuration.temperature,
                        topP: configuration.topP,
                        repetitionPenalty: .some(configuration.repetitionPenalty),
                        repetitionContextSize: configuration.repetitionContextSize
                    )
                )

            for iteration in 1...benchmarkIterationCount() {
                manager.startNewConversation()
                manager.clearConversation()
                manager.currentMode = .chat
                manager.currentInput = prompt
                await LocalModelGenerationPerformanceRecorder.shared.clear()

                let turn = await InferenceMetricsCollector.shared.incrementTurn()
                var timer = InferenceTimer()
                manager.sendMessage()

                let sawFirstToken = try await waitForAssistantFirstToken(in: manager, timeoutSeconds: 90)
                XCTAssertTrue(
                    sawFirstToken,
                    "Expected parameter-sweep run \(configuration.label) iteration \(iteration) to emit assistant output"
                )
                timer.recordFirstToken()

                let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 120)
                XCTAssertFalse(
                    timedOut,
                    "Expected parameter-sweep run \(configuration.label) iteration \(iteration) to finish"
                )

                let finalAssistantContent = manager.messages
                    .filter { $0.role == .assistant && !$0.isDraft }
                    .last?
                    .content
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                XCTAssertFalse(
                    finalAssistantContent.isEmpty,
                    "Expected parameter-sweep run \(configuration.label) iteration \(iteration) to produce text"
                )

                let outputTokenCount = try await LocalModelTokenCounter.shared.tokenCount(
                    text: finalAssistantContent,
                    modelId: runtime.modelId
                )
                let performanceSnapshot = try await waitForLatestLocalPerformanceSnapshot()
                let metric = timer.finalize(
                    testId: testId,
                    modelId: runtime.modelId,
                    inferenceConfiguration: configuration,
                    turn: turn,
                    promptTokens: promptTokenCount,
                    outputTokens: outputTokenCount,
                    performanceSnapshot: performanceSnapshot
                )
                await InferenceMetricsCollector.shared.recordMetrics(metric)
                print(metric.summary)
            }
        }

        guard let aggregateStats = await InferenceMetricsCollector.shared.aggregateStats() else {
            XCTFail("Expected aggregate sweep statistics")
            return
        }

        print(aggregateStats.summary)
        let csv = await InferenceMetricsCollector.shared.exportCSV()
        let csvURL = try saveBenchmarkCSV(csv, testId: testId)
        print("[Inference Metrics] CSV saved to \(csvURL.path)")
    }

    private func waitForLatestLocalPerformanceSnapshot(timeoutSeconds: TimeInterval = 5) async throws
        -> LocalModelGenerationPerformanceSnapshot
    {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let snapshot = await LocalModelGenerationPerformanceRecorder.shared.latest() {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw XCTSkip("Timed out waiting for local MLX performance snapshot")
    }

    func testOfflineHarnessDirectMinimalToolCallProducesAndExecutesCreateFile() async throws {
        let projectRoot = makeTempDir(prefix: "offline_direct_minimal_tools")
        let container = try await makeOfflineContainer(projectRoot: projectRoot)
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot, seedGreeting: false)
        let minimalTools = makeMinimalOfflineTools(projectRoot: projectRoot, eventBus: container.eventBus)
        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: container.aiService,
            codebaseIndex: nil,
            settingsStore: OpenRouterSettingsStore(settingsStore: container.settingsStore),
            eventBus: container.eventBus
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: container.fileSystemService,
            errorManager: NoopErrorManager(),
            projectRoot: projectRoot,
            eventBus: container.eventBus,
            activityCoordinator: container.activityCoordinator
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let fileName = "direct-minimal-offline-\(UUID().uuidString).txt"

        historyCoordinator.append(ChatMessage(
            role: .user,
            content: "Create a file named \(fileName) using the create_file tool, then stop."
        ))

        let responseResult = await aiInteractionCoordinator.sendMessageWithRetry(
            AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages,
                tools: minimalTools,
                mode: .agent,
                projectRoot: projectRoot,
                runId: UUID().uuidString,
                stage: .tool_loop,
                conversationId: historyCoordinator.currentConversationId
            )
        )

        let response = try responseResult.get()
        let toolCalls = try XCTUnwrap(response.toolCalls)
        XCTAssertFalse(toolCalls.isEmpty, "Expected local MLX to emit at least one structured tool call")
        XCTAssertEqual(toolCalls.first?.name, "create_file")

        let toolMessages = await toolExecutionCoordinator.executeToolCalls(
            toolCalls,
            availableTools: minimalTools,
            conversationId: historyCoordinator.currentConversationId
        ) { message in
            if message.toolStatus == .executing {
                historyCoordinator.setLiveToolMessage(message)
            } else {
                historyCoordinator.clearLiveToolMessage(message.toolCallId ?? "")
                historyCoordinator.append(message)
            }
        }

        let completedToolNames = toolMessages
            .filter { $0.isToolExecution && $0.toolStatus == .completed }
            .compactMap(\.toolName)
        XCTAssertTrue(
            completedToolNames.contains("create_file"),
            "Expected executed tool results to include create_file. Results: \(completedToolNames)"
        )

        let completedCreateFileMessages = toolMessages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "create_file"
        }
        XCTAssertTrue(
            completedCreateFileMessages.contains(where: {
                $0.content.contains("Reserved file path at") || $0.content.contains(fileName)
            }),
            "Expected direct minimal local MLX tool call to reserve \(fileName). Messages: \(completedCreateFileMessages.map(\.content))"
        )
    }

    /// Diagnostic test: runs multiple single-turn prompts of varying complexity
    /// to measure thinking vs execution token usage. Outputs a summary table
    /// via [LOCAL-MLX-DIAG] log lines for analysis.
    func testOfflineMLXThinkingBudgetDiagnostic() async throws {
        let prompts: [(label: String, prompt: String, useTools: Bool)] = [
            ("simple_qa", "What is 2 + 2? Answer in one sentence.", false),
            ("medium_explain", "Explain how a hash map works in 3 sentences.", false),
            ("code_explain", "Explain what this code does: func fib(n: Int) -> Int { n < 2 ? n : fib(n-1) + fib(n-2) }", false),
            ("simple_tool", "Create a file named hello.txt with the content 'Hello World'.", true),
            ("medium_tool", "Create a file named config.json with a JSON object containing name, version, and dependencies fields.", true),
            ("complex_tool", "Create a Python file named calculator.py with a Calculator class that supports add, subtract, multiply, and divide operations. Include type hints and docstrings.", true),
        ]

        var results: [(label: String, genTokens: Int, thinkingChars: Int, executionChars: Int, toolCalls: Int, thinkingEnded: Bool)] = []

        for entry in prompts {
            let projectRoot = makeTempDir(prefix: "mlx_diag_\(entry.label)")
            let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot)
            let manager = runtime.manager
            manager.currentMode = .agent
            manager.currentInput = entry.prompt
            manager.sendMessage()

            let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 180)
            print("[LOCAL-MLX-DIAG] label=\(entry.label) timed_out=\(timedOut) useTools=\(entry.useTools)")
            results.append((entry.label, 0, 0, 0, 0, false))
        }

        // Summary table is printed via [LOCAL-MLX-PERF] lines during execution.
        // The thinking_chars, execution_chars, approx_thinking_tokens, approx_execution_tokens,
        // and thinking_ended fields in each PERF line provide the data needed to
        // determine the optimal output token window.
        print("[LOCAL-MLX-DIAG] SUMMARY: \(results.count) prompts completed. See [LOCAL-MLX-PERF] lines for per-prompt thinking vs execution breakdown.")
    }

    func testOfflineHarnessCreateReactAppThroughMLX() async throws {
        let result = try await runOfflineScenarioUntilStable(
            name: "mlx_create_react_app",
            prepare: nil,
            prompt: """
                Create a React application by calling write_file 4 times:
                1. write_file path="package.json" — valid JSON with react and react-dom dependencies
                2. write_file path="index.html" — HTML with root div and script tag
                3. write_file path="src/main.jsx" — React entry point
                4. write_file path="src/App.jsx" — simple counter component
                Do NOT run any commands. Do NOT run npm install. Only use write_file 4 times then stop.
                """,
            timeoutSeconds: 600
        )

        let files = listAllFiles(under: result.projectRoot)
        XCTAssertTrue(files.contains("package.json"), "Expected package.json. Files: \(files)")
        XCTAssertTrue(files.contains("index.html"), "Expected index.html. Files: \(files)")
        XCTAssertTrue(
            files.contains("src/main.jsx") || files.contains("src/main.tsx") || files.contains("src/index.js"),
            "Expected an entry file. Files: \(files)"
        )
        XCTAssertTrue(
            files.contains("src/App.jsx") || files.contains("src/App.tsx") || files.contains("src/App.js"),
            "Expected an app component. Files: \(files)"
        )
    }

    func testOfflineHarnessJavaScriptToTypeScriptMigrationThroughMLX() async throws {
        let result = try await runOfflineScenarioUntilStable(
            name: "mlx_js_to_ts_migration",
            prepare: nil,
            prompt: """
                Create a small JavaScript utility project and migrate it to TypeScript.
                1. Create package.json with build and test scripts
                2. Create src/math.js with add, subtract, and divide functions
                3. Migrate src/math.js to src/math.ts with explicit types
                4. Add tsconfig.json
                5. Remove obsolete JS implementation if replaced
                Use tools only. Keep the project runnable after migration.
                """,
            timeoutSeconds: 140
        )

        let files = listAllFiles(under: result.projectRoot)
        XCTAssertTrue(files.contains("package.json"), "Expected package.json. Files: \(files)")
        XCTAssertTrue(files.contains("tsconfig.json"), "Expected tsconfig.json. Files: \(files)")
        XCTAssertTrue(files.contains("src/math.ts"), "Expected src/math.ts. Files: \(files)")

        let migratedCode = try String(contentsOf: result.projectRoot.appendingPathComponent("src/math.ts"))
        XCTAssertTrue(migratedCode.contains(": number"), "Expected typed signatures in math.ts: \(migratedCode)")
        XCTAssertTrue(
            migratedCode.contains("export") || migratedCode.contains("function"),
            "Expected a usable TypeScript module. Code: \(migratedCode)"
        )
    }

    func testOfflineHarnessAddsTestCoverageThroughMLX() async throws {
        let result = try await runOfflineScenarioUntilStable(
            name: "mlx_add_test_coverage",
            prepare: { root in
                let srcDirectory = root.appendingPathComponent("src", isDirectory: true)
                try FileManager.default.createDirectory(at: srcDirectory, withIntermediateDirectories: true)
                let moduleCode = """
                    export function normalizeName(value) {
                        if (!value) return "";
                        return value.trim().toLowerCase();
                    }

                    export function safeDivide(a, b) {
                        if (b === 0) return null;
                        return a / b;
                    }
                    """
                try moduleCode.write(
                    to: srcDirectory.appendingPathComponent("utils.js"),
                    atomically: true,
                    encoding: .utf8
                )
            },
            prompt: """
                Add full unit test coverage for src/utils.js.
                1. Create package.json with a test script using vitest or jest
                2. Create tests covering normal and edge cases for normalizeName and safeDivide
                3. Ensure divide-by-zero and empty input cases are covered
                4. Keep source behavior unchanged
                Use tools only, then finish.
                """,
            timeoutSeconds: 140
        )

        let files = listAllFiles(under: result.projectRoot)
        XCTAssertTrue(files.contains("package.json"), "Expected package.json. Files: \(files)")

        let candidateTestFiles = files.filter { $0.contains("test") || $0.contains("spec") }
        XCTAssertFalse(candidateTestFiles.isEmpty, "Expected a test file. Files: \(files)")

        if let firstTestPath = candidateTestFiles.first {
            let testCode = try String(contentsOf: result.projectRoot.appendingPathComponent(firstTestPath))
            XCTAssertTrue(
                testCode.localizedCaseInsensitiveContains("normalizeName"),
                "Expected normalizeName coverage in \(firstTestPath): \(testCode)"
            )
            XCTAssertTrue(
                testCode.localizedCaseInsensitiveContains("safeDivide"),
                "Expected safeDivide coverage in \(firstTestPath): \(testCode)"
            )
            XCTAssertTrue(
                testCode.contains("0") || testCode.localizedCaseInsensitiveContains("null"),
                "Expected divide-by-zero handling in \(firstTestPath): \(testCode)"
            )
        }
    }

    // MARK: - Readiness Scenario: Refactoring (Increasing Complexity)

    /// Tests the model's ability to refactor existing code with increasing complexity:
    /// Phase 1: Create a simple utility module with duplicated logic
    /// Phase 2: Refactor to extract shared helper functions and add error handling
    /// Phase 3: Add TypeScript-style JSDoc types and export a clean API surface
    func testOfflineHarnessRefactorIncreasingComplexityThroughMLX() async throws {
        let projectRoot = makeTempDir(prefix: "offline_refactor_complex")
        let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        ToolExecutionTelemetry.shared.reset()

        // Phase 1: Create initial code with duplicated logic
        manager.currentInput = """
            Create a file named src/calculator.js by calling write_file once with this content:
            function add(a, b) { return a + b; }
            function subtract(a, b) { return a - b; }
            function multiply(a, b) { return a * b; }
            function divide(a, b) { return a / b; }
            function addAndDouble(a, b) { return (a + b) * 2; }
            function subtractAndDouble(a, b) { return (a - b) * 2; }
            module.exports = { add, subtract, multiply, divide, addAndDouble, subtractAndDouble };
            Only use write_file, then stop.
            """
        manager.sendMessage()

        let phase1TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 120)
        XCTAssertFalse(phase1TimedOut, "Phase 1 creation timed out")

        let phase1Files = listAllFiles(under: projectRoot)
        XCTAssertTrue(phase1Files.contains("src/calculator.js"), "Expected src/calculator.js after Phase 1. Files: \(phase1Files)")

        // Phase 2: Refactor to extract shared helper and add error handling
        manager.currentInput = """
            Overwrite src/calculator.js by calling write_file with a refactored version:
            - Add a function called "operate" that takes (a, b, fn) and returns fn(a, b)
            - Add divide-by-zero check: if b is 0, throw new Error('Division by zero')
            - Make addAndDouble use operate: return operate(a, b, (x,y) => (x+y)*2)
            - Keep all 6 exports: add, subtract, multiply, divide, addAndDouble, subtractAndDouble
            Call write_file now with path="src/calculator.js" and the full new content. Then stop.
            """
        manager.sendMessage()

        let phase2TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 180)
        XCTAssertFalse(phase2TimedOut, "Phase 2 refactor timed out")

        let refactoredCode = try String(contentsOf: projectRoot.appendingPathComponent("src/calculator.js"))
        XCTAssertTrue(
            refactoredCode.contains("operate") || refactoredCode.contains("apply") || refactoredCode.contains("compute"),
            "Expected extracted helper function in refactored code: \(refactoredCode)"
        )
        XCTAssertTrue(
            refactoredCode.contains("Error") || refactoredCode.contains("throw") || refactoredCode.contains("null") || refactoredCode.contains("undefined"),
            "Expected error handling for divide-by-zero: \(refactoredCode)"
        )

        // Phase 3: Add JSDoc types and clean API
        manager.currentInput = """
            Overwrite src/calculator.js by calling write_file with the same code but adding JSDoc:
            - Add /** @param {number} a @param {number} b @returns {number} */ before each function
            - Add /** @param {number} a @param {number} b @returns {number} @throws {Error} */ before divide
            - Keep all logic exactly the same, only add JSDoc comments above each function
            Call write_file now with path="src/calculator.js" and the full new content. Then stop.
            """
        manager.sendMessage()

        let phase3TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 180)
        XCTAssertFalse(phase3TimedOut, "Phase 3 JSDoc timed out")

        let finalCode = try String(contentsOf: projectRoot.appendingPathComponent("src/calculator.js"))
        XCTAssertTrue(
            finalCode.contains("@param"),
            "Expected JSDoc @param annotations: \(finalCode)"
        )
        XCTAssertTrue(
            finalCode.contains("@returns") || finalCode.contains("@return"),
            "Expected JSDoc @returns annotations: \(finalCode)"
        )

        let totalFailures = manager.messages.filter { $0.isToolExecution && $0.toolStatus == .failed }.count
        XCTAssertLessThanOrEqual(totalFailures, 2, "Expected at most 2 failed tool executions across all phases. Got: \(totalFailures)")
    }

    // MARK: - Readiness Scenario: Terminal Commands (macOS only)

    /// Tests the model's ability to use run_command for macOS terminal operations:
    /// 1. Run `pwd` to verify working directory
    /// 2. Run `ls` to list files
    /// 3. Run `echo` to create a file via terminal
    /// 4. Run `cat` to read the file back
    func testOfflineHarnessTerminalCommandsThroughMLX() async throws {
        let result = try await runOfflineScenarioUntilStable(
            name: "mlx_terminal_commands",
            prepare: nil,
            prompt: """
                Use run_command to perform these terminal operations:
                1. run_command command="echo 'Hello from terminal' > terminal_output.txt" — create a file
                2. run_command command="cat terminal_output.txt" — read the file back
                Call run_command 2 times, then stop.
                """,
            timeoutSeconds: 300
        )

        let files = listAllFiles(under: result.projectRoot)
        XCTAssertTrue(
            files.contains("terminal_output.txt"),
            "Expected terminal_output.txt created via echo. Files: \(files)"
        )

        let outputFile = result.projectRoot.appendingPathComponent("terminal_output.txt")
        let fileContent = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(
            fileContent.contains("Hello from terminal"),
            "Expected file to contain 'Hello from terminal'. Content: \(fileContent)"
        )

        let runCommandMessages = result.manager.messages.filter {
            $0.isToolExecution && $0.toolName == "run_command" && $0.toolStatus == .completed
        }
        XCTAssertGreaterThanOrEqual(
            runCommandMessages.count, 1,
            "Expected at least 1 completed run_command execution. Got: \(runCommandMessages.count)"
        )
    }

    // MARK: - Readiness Scenario: Maximum Context Tool Execution (32K)

    /// Tests whether the model can still execute tools and follow prompts when the context
    /// window is heavily loaded at 32K tokens. Pre-populates large files, instructs the model
    /// to read several of them (filling context with tool response content), then create a
    /// new file that references what it read.
    func testOfflineHarnessMaxContextToolExecutionThroughMLX() async throws {
        let projectRoot = makeTempDir(prefix: "mlx_max_context_32k")
        let srcDir = projectRoot.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        // Create 8 large files (~3KB each) — reading several will fill context
        for i in 1...8 {
            var lines: [String] = []
            lines.append("// Module \(i) — utility functions for subsystem \(i)")
            lines.append("// This module provides data processing, validation, and transformation")
            lines.append("// capabilities for the \(i)th subsystem in the application architecture.")
            lines.append("")
            lines.append("export function process_\(i)(data) {")
            lines.append("    if (!data) return null;")
            lines.append("    if (!Array.isArray(data)) return null;")
            lines.append("    let result = 0;")
            lines.append("    for (let i = 0; i < data.length; i++) {")
            lines.append("        if (typeof data[i] !== 'number') continue;")
            lines.append("        result += data[i] * \(i);")
            lines.append("    }")
            lines.append("    return result;")
            lines.append("}")
            lines.append("")
            lines.append("export function validate_\(i)(input) {")
            lines.append("    if (typeof input !== 'object') return false;")
            lines.append("    if (!Array.isArray(input.data)) return false;")
            lines.append("    if (input.data.length === 0) return false;")
            lines.append("    if (input.data.length > 1000) return false;")
            lines.append("    for (const item of input.data) {")
            lines.append("        if (typeof item !== 'number') return false;")
            lines.append("        if (!isFinite(item)) return false;")
            lines.append("    }")
            lines.append("    return true;")
            lines.append("}")
            lines.append("")
            lines.append("export function transform_\(i)(value, factor) {")
            lines.append("    if (factor === 0) throw new Error('Factor cannot be zero');")
            lines.append("    if (typeof value !== 'number') throw new TypeError('Value must be number');")
            lines.append("    const transformed = value * factor + \(i);")
            lines.append("    return Math.round(transformed * 100) / 100;")
            lines.append("}")
            lines.append("")
            lines.append("export const CONFIG_\(i) = {")
            lines.append("    id: \(i),")
            lines.append("    name: 'module_\(i)',")
            lines.append("    version: '1.0.\(i)',")
            lines.append("    enabled: \(i) % 2 === 0,")
            lines.append("    priority: \(i) * 10,")
            lines.append("    tags: ['utility', 'processor', 'module_\(i)', 'subsystem-\(i)'],")
            lines.append("    metadata: {")
            lines.append("        created: '2025-01-15',")
            lines.append("        author: 'system',")
            lines.append("        checksum: '\(i)a3f\(i)b2c1d\(i)e4f2',")
            lines.append("        dependencies: ['module_\(max(1, i - 1))'],")
            lines.append("    },")
            lines.append("};")
            lines.append("")
            for j in 1...20 {
                lines.append("// Padding line \(j) for module \(i) to increase file size and context usage.")
            }
            let content = lines.joined(separator: "\n")
            try content.write(to: srcDir.appendingPathComponent("module_\(i).js"), atomically: true, encoding: .utf8)
        }

        try """
        {
          "name": "max-context-test",
          "version": "1.0.0",
          "type": "module",
          "scripts": {
            "start": "node src/index.js"
          }
        }
        """.write(
            to: projectRoot.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot, profile: .maxContext)
        let manager = runtime.manager
        manager.currentMode = .agent

        // Apply inference overrides for 262K context with 4-bit KV cache
        let inferenceConfig = runtime.defaultInferenceConfiguration
        await LocalModelInferenceOverrides.shared.set(
            LocalModelInferenceOverrides(
                contextLength: inferenceConfig.contextLength,
                maxKVSize: inferenceConfig.maxKVSize,
                maxOutputTokens: inferenceConfig.maxOutputTokens,
                prefillStepSize: inferenceConfig.prefillStepSize,
                temperature: inferenceConfig.temperature,
                topP: inferenceConfig.topP,
                repetitionPenalty: inferenceConfig.repetitionPenalty,
                repetitionContextSize: inferenceConfig.repetitionContextSize,
                kvCache4BitEnabled: inferenceConfig.kvCache4BitEnabled
            )
        )
        defer {
            Task { await LocalModelInferenceOverrides.shared.clear() }
        }

        ToolExecutionTelemetry.shared.reset()

        // Phase 1: Read files to fill context
        manager.currentInput = """
            Read the following files using read_file:
            1. read_file path="src/module_1.js"
            2. read_file path="src/module_2.js"
            3. read_file path="src/module_3.js"
            4. read_file path="src/module_4.js"
            Read all 4 files, then stop.
            """
        manager.sendMessage()

        let phase1TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 300)
        XCTAssertFalse(phase1TimedOut, "Phase 1 read files timed out at 32K context")

        let readToolMessages = manager.messages.filter {
            $0.isToolExecution && $0.toolName == "read_file" && $0.toolStatus == .completed
        }
        XCTAssertGreaterThanOrEqual(
            readToolMessages.count, 3,
            "Expected at least 3 completed read_file calls to fill context. Got: \(readToolMessages.count)"
        )

        // Phase 2: Write a new file — model must still follow instructions with loaded context
        manager.currentInput = """
            Now call write_file to create src/index.js.
            The file should import process_1 from module_1.js and log the result of processing [1,2,3].
            Call write_file now with path="src/index.js", then stop.
            """
        manager.sendMessage()

        let phase2TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 300)
        XCTAssertFalse(phase2TimedOut, "Phase 2 write_file timed out at 32K context")

        let files = listAllFiles(under: projectRoot)
        XCTAssertTrue(
            files.contains("src/index.js"),
            "Expected src/index.js created at 32K context. Files: \(files)"
        )

        let indexContent = try String(contentsOf: projectRoot.appendingPathComponent("src/index.js"))
        XCTAssertTrue(
            indexContent.contains("import") || indexContent.contains("require"),
            "Expected import/require in index.js: \(indexContent)"
        )
        XCTAssertTrue(
            indexContent.contains("process_1") || indexContent.contains("module_1"),
            "Expected reference to module_1/process_1 in index.js: \(indexContent)"
        )

        let writeToolMessages = manager.messages.filter {
            $0.isToolExecution && $0.toolName == "write_file" && $0.toolStatus == .completed
        }
        XCTAssertGreaterThanOrEqual(
            writeToolMessages.count, 1,
            "Expected at least 1 completed write_file at 32K context."
        )
    }

    func testOfflineHarnessReactTodoToSSRRefactorThroughMLX() async throws {
        let projectRoot = makeTempDir(prefix: "offline_ssr_refactor")
        let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        ToolExecutionTelemetry.shared.reset()
        manager.currentInput = """
            Create a simple React Todo application structure using vite.
            1. Create package.json with react and react-dom dependencies
            2. Create index.html
            3. Create src/main.jsx
            4. Create src/App.jsx with a functional todo list (add, toggle, delete)
            Do not run npm install. Only create files using tools, then finish.
            """
        manager.sendMessage()

        let buildTimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 150)
        XCTAssertFalse(buildTimedOut, "Phase 1 build timed out for MLX SSR scenario")

        let buildFailures = manager.messages.filter { $0.isToolExecution && $0.toolStatus == .failed }.count
        XCTAssertEqual(buildFailures, 0, "Phase 1 build should avoid failed tool executions")

        manager.currentInput = """
            Now refactor this application into a Server-Side Rendered (SSR) setup using a simple Express server.
            1. Add express to package.json
            2. Create a server.js file at the root that serves the React app using ReactDOMServer.renderToString
            3. Modify index.html and src/main.jsx to support hydration
            Do not run npm install. Only implement file changes using tools, then finish.
            """
        manager.sendMessage()

        let refactorTimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 180)
        XCTAssertFalse(refactorTimedOut, "Phase 2 SSR refactor timed out for MLX")

        let files = listAllFiles(under: projectRoot)
        XCTAssertTrue(files.contains("package.json"), "Expected package.json after SSR phases. Files: \(files)")
        XCTAssertTrue(files.contains("index.html"), "Expected index.html after SSR phases. Files: \(files)")
        XCTAssertTrue(
            files.contains("src/App.jsx") || files.contains("src/App.tsx") || files.contains("src/App.js"),
            "Expected App component after SSR phases. Files: \(files)"
        )
        XCTAssertTrue(
            files.contains("server.js") || files.contains("server/index.js"),
            "Expected SSR server entrypoint. Files: \(files)"
        )

        let serverPath = files.contains("server.js") ? "server.js" : "server/index.js"
        let serverCode = try String(contentsOf: projectRoot.appendingPathComponent(serverPath))
        XCTAssertTrue(serverCode.contains("express"), "Expected express in SSR server: \(serverCode)")
        XCTAssertTrue(
            serverCode.contains("renderToString") || serverCode.contains("renderToPipeableStream"),
            "Expected SSR render API in server: \(serverCode)"
        )
    }

    func testOfflineHarnessBlocksExternalAPIsWhenOfflineDisabled() async throws {
        let runtime = try await makeRuntime(offlineModeEnabled: false)
        let manager = runtime.manager
        manager.currentMode = .agent

        manager.currentInput = "Create a file named api-blocked.txt"
        manager.sendMessage()

        try await waitForConversationToFinish(manager, timeoutSeconds: 30)
        let errorText = manager.error ?? ""
        XCTAssertTrue(
            errorText.contains("External APIs are disabled in test configuration"),
            "Expected external API block error, got: \(errorText)"
        )
    }

    private struct Runtime {
        let manager: ConversationManager
        let modelId: String
        let defaultInferenceConfiguration: LocalModelInferenceConfiguration
    }

    private enum RuntimeProfile {
        case standard
        case benchmark
        case maxContext
    }

    private struct ScenarioResult {
        let projectRoot: URL
        let manager: ConversationManager
        let telemetry: ToolExecutionTelemetrySummary
    }

    private func resolveOfflineHarnessModelId(preferredModelId: String?) async throws -> String {
        let model = LocalModelCatalog.defaultModel

        if !LocalModelFileStore.isModelInstalled(model) {
            print("[HARNESS] Model not installed, downloading \(model.displayName)...")
            let downloader = LocalModelDownloader()
            try await downloader.download(model: model) { progress in
                if progress.fractionCompleted > 0 {
                    print("[HARNESS] Download progress: \(Int(progress.fractionCompleted * 100))%")
                }
            }
            print("[HARNESS] Model download complete.")
        }

        return model.id
    }

    private func preferredOfflineHarnessModelId(settingsStore: SettingsStore) -> String? {
        LocalModelCatalog.defaultModel.id
    }

    private func makeRuntime(
        offlineModeEnabled: Bool,
        projectRoot: URL? = nil,
        profile: RuntimeProfile = .standard
    ) async throws -> Runtime {
        let container = try await makeConfiguredContainer(
            offlineModeEnabled: offlineModeEnabled,
            projectRoot: projectRoot,
            profile: profile
        )

        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "OfflineModeHarnessTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected conversation manager type"]
            )
        }

        manager.startNewConversation()
        manager.clearConversation()

        let modelId = container.settingsStore.string(forKey: "LocalModel.SelectedId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultInferenceConfiguration = try defaultInferenceConfiguration(
            for: modelId,
            profile: profile
        )
        return Runtime(
            manager: manager,
            modelId: modelId,
            defaultInferenceConfiguration: defaultInferenceConfiguration
        )
    }

    private func makeOfflineContainer(projectRoot: URL? = nil) async throws -> DependencyContainer {
        try await makeConfiguredContainer(
            offlineModeEnabled: true,
            projectRoot: projectRoot,
            profile: .standard
        )
    }

    private func makeConfiguredContainer(
        offlineModeEnabled: Bool,
        projectRoot: URL?,
        profile: RuntimeProfile
    ) async throws -> DependencyContainer {
        let environment = ProcessInfo.processInfo.environment
        let testProfilePath: String?
        let disableHeavyInit: Bool

        switch profile {
        case .standard:
            testProfilePath = environment[TestLaunchKeys.testProfileDir]
                ?? environment["TEST_RUNNER_ENV_OSXIDE_TEST_PROFILE_DIR"]
            disableHeavyInit = false
        case .benchmark:
            let basePath = environment[TestLaunchKeys.testProfileDir]
                ?? environment["TEST_RUNNER_ENV_OSXIDE_TEST_PROFILE_DIR"]
                ?? NSTemporaryDirectory()
            let benchmarkProfileDirectory = URL(fileURLWithPath: basePath, isDirectory: true)
                .appendingPathComponent("benchmark-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: benchmarkProfileDirectory,
                withIntermediateDirectories: true
            )
            testProfilePath = benchmarkProfileDirectory.path
            disableHeavyInit = true
        case .maxContext:
            testProfilePath = environment[TestLaunchKeys.testProfileDir]
                ?? environment["TEST_RUNNER_ENV_OSXIDE_TEST_PROFILE_DIR"]
            disableHeavyInit = false
        }

        let container = DependencyContainer(
            launchContext: AppLaunchContext(
                mode: .unitTest,
                isTesting: true,
                isUITesting: false,
                testProfilePath: testProfilePath,
                disableHeavyInit: disableHeavyInit,
                productionParityHarness: profile == .benchmark
            )
        )

        let openRouterSettingsStore = OpenRouterSettingsStore(settingsStore: container.settingsStore)
        let currentSettings = openRouterSettingsStore.load(includeApiKey: true)
        openRouterSettingsStore.save(OpenRouterSettings(
            apiKey: currentSettings.apiKey,
            model: currentSettings.model,
            baseURL: currentSettings.baseURL,
            systemPrompt: currentSettings.systemPrompt,
            reasoningMode: currentSettings.reasoningMode,
            toolPromptMode: currentSettings.toolPromptMode
        ))

        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        container.settingsStore.set(offlineModeEnabled, forKey: "AI.OfflineModeEnabled")
        await selectionStore.setOfflineModeEnabled(offlineModeEnabled)
        if offlineModeEnabled {
            let modelId = try await resolveOfflineHarnessModelId(
                preferredModelId: preferredOfflineHarnessModelId(settingsStore: container.settingsStore)
            )
            container.settingsStore.set(modelId, forKey: "LocalModel.SelectedId")
            await selectionStore.setSelectedModelId(modelId)
            XCTAssertEqual(container.settingsStore.string(forKey: "LocalModel.SelectedId"), modelId)
            let effectiveModelId = await selectionStore.selectedModelId()
            XCTAssertEqual(effectiveModelId, modelId)
        }
        let effectiveOfflineMode = await selectionStore.isOfflineModeEnabled()
        XCTAssertEqual(effectiveOfflineMode, offlineModeEnabled)

        if let projectRoot {
            container.workspaceService.currentDirectory = projectRoot
            container.projectCoordinator.configureProject(root: projectRoot)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        return container
    }

    private func makeMinimalSendCoordinator(
        projectRoot: URL,
        container: DependencyContainer,
        historyCoordinator: ChatHistoryCoordinator
    ) -> ConversationSendCoordinator {
        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: container.aiService,
            codebaseIndex: nil,
            settingsStore: OpenRouterSettingsStore(settingsStore: container.settingsStore),
            eventBus: container.eventBus
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: container.fileSystemService,
            errorManager: NoopErrorManager(),
            projectRoot: projectRoot,
            eventBus: container.eventBus,
            activityCoordinator: container.activityCoordinator
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        return ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )
    }

    private func makeHistoryCoordinator(projectRoot: URL, seedGreeting: Bool = true) -> ChatHistoryCoordinator {
        let historyCoordinator = ChatHistoryCoordinator(
            
            projectRoot: projectRoot
        )
        if seedGreeting {
            historyCoordinator.append(ChatMessage(role: .user, content: "Hello"))
        }
        return historyCoordinator
    }

    private func makeMinimalOfflineTools(projectRoot: URL, eventBus: EventBusProtocol) -> [AITool] {
        let pathValidator = PathValidator(projectRoot: projectRoot)
        let fileSystemService = FileSystemService()
        return [
            WriteFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator, eventBus: eventBus),
            ListFilesTool(pathValidator: pathValidator),
            ReadFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator)
        ]
    }

    private func runOfflineScenarioUntilStable(
        name: String,
        prepare: ((URL) throws -> Void)?,
        prompt: String,
        timeoutSeconds: TimeInterval,
        profile: RuntimeProfile = .standard
    ) async throws -> ScenarioResult {
        var lastResult: ScenarioResult?

        for attempt in 1...maxScenarioAttempts {
            let projectRoot = makeTempDir(prefix: name)
            try prepare?(projectRoot)

            ToolExecutionTelemetry.shared.reset()
            let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot, profile: profile)
            let manager = runtime.manager
            manager.currentMode = .agent
            manager.currentInput = prompt
            manager.sendMessage()

            let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: timeoutSeconds)
            let telemetry = ToolExecutionTelemetry.shared.summary
            let failedToolExecutions = manager.messages.filter { $0.isToolExecution && $0.toolStatus == .failed }.count
            let repeatedToolCallSignatures = telemetry.repeatedToolCallSignatures
            let gatePassed = !timedOut && failedToolExecutions == 0 && repeatedToolCallSignatures == 0
            let result = ScenarioResult(projectRoot: projectRoot, manager: manager, telemetry: telemetry)
            lastResult = result

            print("[OFFLINE-MLX][GATE] scenario=\(name) attempt=\(attempt) passed=\(gatePassed) repeated=\(repeatedToolCallSignatures) failed_tools=\(failedToolExecutions) timed_out=\(timedOut)")

            if gatePassed {
                return result
            }
        }

        guard let fallback = lastResult else {
            throw NSError(
                domain: "OfflineModeHarnessTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No offline MLX scenario attempts executed for \(name)"]
            )
        }

        let failedToolExecutions = fallback.manager.messages.filter { $0.isToolExecution && $0.toolStatus == .failed }.count
        XCTFail(
            "Offline MLX scenario \(name) did not reach clean gate after \(maxScenarioAttempts) attempts. " +
            "failedToolExecutions=\(failedToolExecutions) repeatedToolCallSignatures=\(fallback.telemetry.repeatedToolCallSignatures)"
        )
        return fallback
    }

    private func waitForConversationToFinish(
        _ manager: ConversationManager,
        timeoutSeconds: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !manager.isSending {
                return false
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if !manager.isSending {
            return false
        }

        let observedExecutionStatuses = manager.messages
            .filter { $0.isToolExecution }
            .map { message in
                let toolName = message.toolName ?? "unknown_tool"
                let status = message.toolStatus?.rawValue ?? "nil"
                return "\(toolName)[\(status)]"
            }
        let failedSummaries = manager.messages
            .filter { $0.isToolExecution && $0.toolStatus == .failed }
            .map { message in
                let toolName = message.toolName ?? "unknown_tool"
                return "\(toolName): \(message.content.prefix(160))"
            }
        let recentMessageSummaries = manager.messages.suffix(6).map { message in
            let toolName = message.toolName ?? "-"
            let status = message.toolStatus?.rawValue ?? "-"
            return "\(message.role.rawValue):\(toolName):\(status): \(message.content.prefix(160))"
        }

        XCTFail(
            "Timed out waiting for conversation manager to finish send task. "
                + "Observed tool statuses: \(observedExecutionStatuses). "
                + "Failed tool summaries: \(failedSummaries). "
                + "Recent messages: \(recentMessageSummaries)"
        )
        return true
    }

    private func waitForAssistantFirstToken(
        in manager: ConversationManager,
        timeoutSeconds: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let assistantText = manager.messages
                .filter { $0.role == .assistant }
                .map(\.content)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !assistantText.isEmpty {
                return true
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func waitForCompletedToolExecution(
        named toolName: String,
        in manager: ConversationManager,
        timeoutSeconds: TimeInterval
    ) async throws -> ChatMessage {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let completedMessage = manager.messages.last(where: {
                $0.isToolExecution
                    && $0.toolName == toolName
                    && $0.toolStatus == .completed
            }) {
                return completedMessage
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("Timed out waiting for local MLX agent to complete \(toolName)")
        return ChatMessage(role: .system, content: "timeout")
    }

    private func waitForCompletedToolExecutions(
        requiredToolNames: [[String]],
        in manager: ConversationManager,
        timeoutSeconds: TimeInterval
    ) async throws -> [ChatMessage] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let completedMessages = manager.messages.filter {
                $0.isToolExecution && $0.toolStatus == .completed
            }
            let completedToolNames = Set(completedMessages.compactMap(\.toolName))
            let hasSatisfiedRequirements = requiredToolNames.allSatisfy { requiredNames in
                !Set(requiredNames).intersection(completedToolNames).isEmpty
            }
            if hasSatisfiedRequirements {
                return completedMessages
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let completedSummaries = manager.messages
            .filter { $0.isToolExecution && $0.toolStatus == .completed }
            .map { message in
                let toolName = message.toolName ?? "unknown_tool"
                return "\(toolName): \(message.content.prefix(120))"
            }
        let failedSummaries = manager.messages
            .filter { $0.isToolExecution && $0.toolStatus == .failed }
            .map { message in
                let toolName = message.toolName ?? "unknown_tool"
                return "\(toolName): \(message.content.prefix(120))"
            }
        let observedExecutionStatuses = manager.messages
            .filter { $0.isToolExecution }
            .map { message in
                let toolName = message.toolName ?? "unknown_tool"
                let status = message.toolStatus?.rawValue ?? "nil"
                return "\(toolName)[\(status)]"
            }

        XCTFail(
            "Timed out waiting for local MLX agent to complete required tool categories \(requiredToolNames). "
                + "Completed: \(completedSummaries). Failed: \(failedSummaries). Observed: \(observedExecutionStatuses)"
        )
        return []
    }

    private func finishOrCancelGeneration(
        _ manager: ConversationManager,
        gracefulWaitSeconds: TimeInterval
    ) async throws {
        let gracefulDeadline = Date().addingTimeInterval(gracefulWaitSeconds)
        while Date() < gracefulDeadline {
            if !manager.isSending {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        if manager.isSending {
            manager.stopGeneration()
            try await waitForConversationToFinish(manager, timeoutSeconds: 5)
        }
    }

    private func makeTempDir(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func listAllFiles(under directory: URL) -> [String] {
        let fileManager = FileManager.default
        let basePath = directory.standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let filePath = url.standardizedFileURL.path
            let relative = String(filePath.dropFirst(basePath.count + 1))
            if !relative.hasPrefix(AppConstantsFileSystem.projectDirName) {
                files.append(relative)
            }
        }
        return files.sorted()
    }

    private func benchmarkIterationCount() -> Int {
        let configuredIterations = benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_ITERATIONS")
            .flatMap(Int.init)
        return max(1, min(configuredIterations ?? 3, 20))
    }

    private func benchmarkPromptTargetTokenCount() -> Int {
        let configuredTarget = benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_PROMPT_TOKENS")
            .flatMap(Int.init)
        return max(128, min(configuredTarget ?? 1024, 12_000))
    }

    private func defaultInferenceConfiguration(
        for modelId: String,
        profile: RuntimeProfile
    ) throws -> LocalModelInferenceConfiguration {
        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw NSError(
                domain: "OfflineModeHarnessTests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Missing local model definition for \(modelId)"]
            )
        }

        let maxContextLength: Int
        switch profile {
        case .standard:
            maxContextLength = 8192
        case .benchmark:
            maxContextLength = 8192
        case .maxContext:
            maxContextLength = 262144
        }

        let contextLength = min(LocalModelFileStore.contextLength(for: model), maxContextLength)
        let defaultMaxOutputTokens: Int
        switch profile {
        case .standard:
            defaultMaxOutputTokens = min(2048, max(768, contextLength / 3))
        case .benchmark:
            defaultMaxOutputTokens = min(2048, max(512, contextLength / 4))
        case .maxContext:
            defaultMaxOutputTokens = min(4096, max(2048, contextLength / 8))
        }
        return LocalModelInferenceConfiguration(
            contextLength: contextLength,
            maxKVSize: contextLength,
            maxOutputTokens: defaultMaxOutputTokens,
            prefillStepSize: 512,
            temperature: 0.35,
            topP: 0.92,
            repetitionPenalty: 1.03,
            repetitionContextSize: 64,
            kvCache4BitEnabled: true
        )
    }

    private func benchmarkConfigurations(
        defaultConfiguration: LocalModelInferenceConfiguration
    ) -> [LocalModelInferenceConfiguration] {
        let contexts = parseBenchmarkList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_CONTEXTS")
        ) ?? [defaultConfiguration.contextLength, min(4096, max(defaultConfiguration.contextLength, 3072))]
        let maxKVSizes = parseBenchmarkList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_MAX_KV_SIZES")
        ) ?? [min(defaultConfiguration.maxKVSize, 2048), defaultConfiguration.maxKVSize]
        let maxOutputs = parseBenchmarkList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_MAX_OUTPUTS")
        ) ?? [defaultConfiguration.maxOutputTokens]
        let prefillSteps = parseBenchmarkList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_PREFILL_STEPS")
        ) ?? [256, 512, 1024]
        let temperatures = parseBenchmarkFloatList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_TEMPERATURES")
        ) ?? [defaultConfiguration.temperature]
        let topPs = parseBenchmarkFloatList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_TOP_P")
        ) ?? [defaultConfiguration.topP]
        let repetitionPenalties = parseBenchmarkOptionalFloatList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_REPETITION_PENALTIES")
        ) ?? [defaultConfiguration.repetitionPenalty]
        let repetitionContextSizes = parseBenchmarkList(
            benchmarkEnvironmentValue("OSXIDE_OFFLINE_BENCHMARK_REPETITION_CONTEXT_SIZES")
        ) ?? [defaultConfiguration.repetitionContextSize]

        var configurations: [LocalModelInferenceConfiguration] = []
        for contextLength in contexts {
            for maxKVSize in maxKVSizes {
                guard maxKVSize <= contextLength else { continue }
                for maxOutputTokens in maxOutputs {
                    for prefillStepSize in prefillSteps {
                        for temperature in temperatures {
                            for topP in topPs {
                                for repetitionPenalty in repetitionPenalties {
                                    for repetitionContextSize in repetitionContextSizes {
                                        configurations.append(
                                            LocalModelInferenceConfiguration(
                                                contextLength: contextLength,
                                                maxKVSize: maxKVSize,
                                                maxOutputTokens: maxOutputTokens,
                                                prefillStepSize: prefillStepSize,
                                                temperature: temperature,
                                                topP: topP,
                                                repetitionPenalty: repetitionPenalty,
                                                repetitionContextSize: repetitionContextSize,
                                                kvCache4BitEnabled: false
                                            )
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return Array(Set(configurations)).sorted { lhs, rhs in
            if lhs.contextLength != rhs.contextLength {
                return lhs.contextLength < rhs.contextLength
            }
            if lhs.maxKVSize != rhs.maxKVSize {
                return lhs.maxKVSize < rhs.maxKVSize
            }
            if lhs.maxOutputTokens != rhs.maxOutputTokens {
                return lhs.maxOutputTokens < rhs.maxOutputTokens
            }
            if lhs.prefillStepSize != rhs.prefillStepSize {
                return lhs.prefillStepSize < rhs.prefillStepSize
            }
            if lhs.temperature != rhs.temperature {
                return lhs.temperature < rhs.temperature
            }
            if lhs.topP != rhs.topP {
                return lhs.topP < rhs.topP
            }
            if lhs.repetitionPenalty != rhs.repetitionPenalty {
                return (lhs.repetitionPenalty ?? 0) < (rhs.repetitionPenalty ?? 0)
            }
            return lhs.repetitionContextSize < rhs.repetitionContextSize
        }
    }

    private func parseBenchmarkList(_ rawValue: String?) -> [Int]? {
        guard let rawValue else { return nil }
        let values = rawValue
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
        return values.isEmpty ? nil : values
    }

    private func parseBenchmarkFloatList(_ rawValue: String?) -> [Float]? {
        guard let rawValue else { return nil }
        let values = rawValue
            .split(separator: ",")
            .compactMap { token -> Float? in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return Float(trimmed)
            }
        return values.isEmpty ? nil : values
    }

    private func parseBenchmarkOptionalFloatList(_ rawValue: String?) -> [Float?]? {
        guard let rawValue else { return nil }
        let values = rawValue
            .split(separator: ",")
            .compactMap { token -> Float?? in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !trimmed.isEmpty else { return nil }
                if trimmed == "nil" || trimmed == "none" || trimmed == "off" {
                    return .some(nil)
                }
                guard let value = Float(trimmed) else { return nil }
                return .some(value)
            }
        return values.isEmpty ? nil : values
    }

    private func benchmarkEnvironmentValue(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_ENV_\(key)"]
    }

    private func makeLongBenchmarkPrompt(modelId: String, targetTokens: Int) async throws -> String {
        let instruction = "Read the following context carefully. Then reply with exactly one short sentence that starts with READY: and contains at most eight words.\n\n"
        let chunk = "Project context block: This repository runs a local MLX model, we are tuning context length, KV cache size, and prefill chunking to avoid swap and maximize throughput on Apple silicon.\n"
        var prompt = instruction

        while try await LocalModelTokenCounter.shared.tokenCount(text: prompt, modelId: modelId) < targetTokens {
            prompt += chunk
        }

        return prompt
    }

    private func saveBenchmarkCSV(_ csv: String, testId: String) throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let preferredDirectory = environment[TestLaunchKeys.testProfileDir]
            ?? environment["TEST_RUNNER_ENV_OSXIDE_TEST_PROFILE_DIR"]
        let baseDirectory = preferredDirectory.map(URL.init(fileURLWithPath:))
            ?? FileManager.default.temporaryDirectory
        let benchmarkDirectory = baseDirectory.appendingPathComponent("inference-benchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: benchmarkDirectory, withIntermediateDirectories: true)
        let csvURL = benchmarkDirectory.appendingPathComponent("\(testId).csv")
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        return csvURL
    }

    // MARK: - Pressure Test: 262K Context with 4-bit KV Cache

    /// Pressure test that fills the 262K context window with many large file reads,
    /// then verifies the model can still reason about content from early in the conversation.
    /// This tests whether the sliding window preserves reasoning and tool execution
    /// when the KV cache is quantized to 4-bit.
    func testOfflineHarness262KContextPressureWithKV4Bit() async throws {
        let projectRoot = makeTempDir(prefix: "mlx_262k_pressure")
        let srcDir = projectRoot.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        // Create 40 large files (~8KB each, ~320KB total ≈ ~80K+ tokens of content)
        // Each file has a unique marker string the model must recall later.
        let fileCount = 40
        for i in 1...fileCount {
            var lines: [String] = []
            lines.append("// File \(i) of \(fileCount) — data processing module #\(i)")
            lines.append("// MARKER: The secret code for module \(i) is CODE-\(i * 137)-ALPHA")
            lines.append("// This module handles batch processing pipeline stage \(i).")
            lines.append("")
            lines.append("export class Processor\(i) {")
            lines.append("    constructor(config) {")
            lines.append("        this.id = \(i);")
            lines.append("        this.name = 'processor_\(i)';")
            lines.append("        this.version = '2.\(i).0';")
            lines.append("        this.config = config || {};")
            lines.append("        this.queue = [];")
            lines.append("        this.processed = 0;")
            lines.append("        this.errors = [];")
            lines.append("    }")
            lines.append("")
            lines.append("    enqueue(item) {")
            lines.append("        if (!item) throw new Error('Cannot enqueue empty item');")
            lines.append("        if (typeof item !== 'object') throw new TypeError('Item must be object');")
            lines.append("        this.queue.push(item);")
            lines.append("        return this.queue.length;")
            lines.append("    }")
            lines.append("")
            lines.append("    dequeue() {")
            lines.append("        if (this.queue.length === 0) return null;")
            lines.append("        return this.queue.shift();")
            lines.append("    }")
            lines.append("")
            lines.append("    process() {")
            lines.append("        const item = this.dequeue();")
            lines.append("        if (!item) return null;")
            lines.append("        const result = {")
            lines.append("            processorId: this.id,")
            lines.append("            input: item,")
            lines.append("            output: this.transform(item),")
            lines.append("            timestamp: Date.now(),")
            lines.append("        };")
            lines.append("        this.processed++;")
            lines.append("        return result;")
            lines.append("    }")
            lines.append("")
            lines.append("    transform(item) {")
            lines.append("        let value = 0;")
            lines.append("        for (const key of Object.keys(item)) {")
            lines.append("            if (typeof item[key] === 'number') {")
            lines.append("                value += item[key] * this.id;")
            lines.append("            }")
            lines.append("        }")
            lines.append("        return { value, scaled: value * \(i), module: this.name };")
            lines.append("    }")
            lines.append("")
            lines.append("    batchProcess(count) {")
            lines.append("        const results = [];")
            lines.append("        for (let i = 0; i < count && this.queue.length > 0; i++) {")
            lines.append("            const r = this.process();")
            lines.append("            if (r) results.push(r);")
            lines.append("        }")
            lines.append("        return results;")
            lines.append("    }")
            lines.append("")
            lines.append("    getStatus() {")
            lines.append("        return {")
            lines.append("            id: this.id,")
            lines.append("            name: this.name,")
            lines.append("            queueLength: this.queue.length,")
            lines.append("            processed: this.processed,")
            lines.append("            errors: this.errors.length,")
            lines.append("        };")
            lines.append("    }")
            lines.append("}")
            lines.append("")
            lines.append("export const FACTORY_\(i) = {")
            lines.append("    create: (config) => new Processor\(i)(config),")
            lines.append("    id: \(i),")
            lines.append("    type: 'processor',")
            lines.append("    priority: \(i) * 5,")
            lines.append("};")
            lines.append("")
            // Pad with comments to increase file size
            for j in 1...60 {
                lines.append("// Padding section \(j) for file \(i): additional context data for pipeline stage \(i) step \(j).")
                lines.append("// Configuration block \(j): { threshold: \(j * 10), timeout: \(j * 100), retries: \(j % 3) }")
            }
            lines.append("")
            let content = lines.joined(separator: "\n")
            try content.write(to: srcDir.appendingPathComponent("module_\(i).js"), atomically: true, encoding: .utf8)
        }

        try """
        {
          "name": "context-pressure-test",
          "version": "1.0.0",
          "type": "module",
          "scripts": {
            "start": "node src/index.js"
          }
        }
        """.write(
            to: projectRoot.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot, profile: .maxContext)
        let manager = runtime.manager
        manager.currentMode = .agent

        // Apply inference overrides for 262K context with 4-bit KV cache
        let inferenceConfig = runtime.defaultInferenceConfiguration
        await LocalModelInferenceOverrides.shared.set(
            LocalModelInferenceOverrides(
                contextLength: inferenceConfig.contextLength,
                maxKVSize: nil,
                maxOutputTokens: inferenceConfig.maxOutputTokens,
                prefillStepSize: nil,
                temperature: inferenceConfig.temperature,
                topP: inferenceConfig.topP,
                repetitionPenalty: inferenceConfig.repetitionPenalty,
                repetitionContextSize: inferenceConfig.repetitionContextSize,
                kvCache4BitEnabled: true
            )
        )
        defer {
            Task { await LocalModelInferenceOverrides.shared.clear() }
        }

        ToolExecutionTelemetry.shared.reset()

        // Phase 1: Read all 40 files to fill context heavily
        // Build a prompt that asks for all files in batches
        var fileList = ""
        for i in 1...fileCount {
            fileList += "read_file path=\"src/module_\(i).js\"\n"
        }

        manager.currentInput = """
            Read ALL of the following files using read_file. Read every single one, then stop.
            Do not summarize or skip any file. Read them all.

            \(fileList)

            After reading all files, stop and wait for further instructions.
            """
        manager.sendMessage()

        let phase1TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 600)
        XCTAssertFalse(phase1TimedOut, "Phase 1 (read 40 files) timed out")

        let readToolMessages = manager.messages.filter {
            $0.isToolExecution && $0.toolName == "read_file" && $0.toolStatus == .completed
        }
        print("[PRESSURE-TEST] Phase 1: \(readToolMessages.count) read_file calls completed out of \(fileCount) expected")

        // Phase 2: Ask the model to recall the marker from file 1 (tests if early context is preserved)
        manager.currentInput = """
            I need you to recall specific information from the files you just read.
            In module_1.js, there is a MARKER line with a secret code.
            What is the exact secret code for module 1? Reply with just the code.
            """
        manager.sendMessage()

        let phase2TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 300)
        XCTAssertFalse(phase2TimedOut, "Phase 2 (recall marker) timed out")

        // Check if the model recalled the marker — it should contain "CODE-137-ALPHA"
        let phase2Response = manager.messages.last(where: { $0.role == .assistant })?.content ?? ""
        print("[PRESSURE-TEST] Phase 2 recall response: \(phase2Response.prefix(300))")
        XCTAssertTrue(
            phase2Response.contains("137") || phase2Response.contains("CODE"),
            "Model should recall the marker code from module_1.js. Got: \(phase2Response.prefix(200))"
        )

        // Phase 3: Ask the model to write a file that references multiple modules (tests reasoning + tool execution)
        manager.currentInput = """
            Now create a file src/index.js that imports Processor1 from module_1.js and Processor40 from module_40.js.
            Create an instance of each, enqueue some test data, process it, and log the results.
            Use write_file to create src/index.js, then stop.
            """
        manager.sendMessage()

        let phase3TimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 300)
        XCTAssertFalse(phase3TimedOut, "Phase 3 (write index.js) timed out")

        let files = listAllFiles(under: projectRoot)
        XCTAssertTrue(
            files.contains("src/index.js"),
            "Expected src/index.js created. Files: \(files)"
        )

        if files.contains("src/index.js") {
            let indexContent = try String(contentsOf: projectRoot.appendingPathComponent("src/index.js"))
            print("[PRESSURE-TEST] Phase 3 index.js content (first 500 chars): \(indexContent.prefix(500))")
            XCTAssertTrue(
                indexContent.contains("module_1") || indexContent.contains("Processor1"),
                "Expected reference to module_1/Processor1 in index.js: \(indexContent.prefix(200))"
            )
            XCTAssertTrue(
                indexContent.contains("module_40") || indexContent.contains("Processor40"),
                "Expected reference to module_40/Processor40 in index.js: \(indexContent.prefix(200))"
            )
        }

        let writeToolMessages = manager.messages.filter {
            $0.isToolExecution && $0.toolName == "write_file" && $0.toolStatus == .completed
        }
        print("[PRESSURE-TEST] Phase 3: \(writeToolMessages.count) write_file calls completed")

        // Summary
        let allToolMessages = manager.messages.filter { $0.isToolExecution }
        let completedTools = allToolMessages.filter { $0.toolStatus == .completed }
        let failedTools = allToolMessages.filter { $0.toolStatus == .failed }
        print("[PRESSURE-TEST] Summary: \(allToolMessages.count) total tools, \(completedTools.count) completed, \(failedTools.count) failed")
        print("[PRESSURE-TEST] Total messages in conversation: \(manager.messages.count)")
    }
}
