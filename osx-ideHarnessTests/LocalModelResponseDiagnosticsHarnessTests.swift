import XCTest
@testable import osx_ide

/// Harness test that sends prompts to the local MLX model, collects telemetry,
/// and asserts that responses contain visible output and properly mapped reasoning.
///
/// Run with:
///   ./run.sh harness LocalModelResponseDiagnosticsHarnessTests
///
/// This test is self-contained — it boots the local model, sends a prompt,
/// waits for completion, and prints detailed diagnostics about:
/// - Raw response content and reasoning
/// - Whether splitReasoning extracted reasoning correctly
/// - Whether the AIServiceResponse.reasoning field was set
/// - Delivery status and message visibility
/// - Telemetry log entries from the run
@MainActor
final class LocalModelResponseDiagnosticsHarnessTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        await LocalModelInferenceOverrides.shared.clear()
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Send a simple greeting prompt and verify the model produces visible output.
    /// Prints detailed diagnostics about reasoning extraction and response structure.
    func testDiagnosticsSimpleGreetingProducesVisibleOutput() async throws {
        let projectRoot = makeTempDir(prefix: "diag_greeting")
        let runtime = try await makeRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .chat

        let prompt = "Reply with exactly one short greeting sentence and stop."
        let runId = UUID().uuidString

        await AIToolTraceLogger.shared.setProjectRoot(projectRoot)
        let traceLogPath = await AIToolTraceLogger.shared.currentLogFilePath()
        print("[DIAG] Trace log: \(traceLogPath)")

        manager.currentInput = prompt
        manager.sendMessage()

        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 90)
        XCTAssertFalse(timedOut, "Diagnostics greeting run timed out")

        printDiagnostics(manager: manager, runtime: runtime, prompt: prompt, runId: runId)

        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        XCTAssertFalse(assistantMessages.isEmpty, "Expected at least one assistant message")

        let finalContent = assistantMessages.last?.content ?? ""
        let trimmedContent = finalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(trimmedContent.isEmpty, "Expected non-empty visible content. Got: '\(finalContent)'")

        // Check that the content is not just the fallback "no user-visible response" message
        XCTAssertFalse(
            trimmedContent.contains("Assistant returned no user-visible response"),
            "Model produced empty response — content was replaced by fallback. Check reasoning extraction."
        )
    }

    /// Send an agent-mode prompt that requires tool use and verify the response chain.
    func testDiagnosticsAgentModeToolUseProducesVisibleOutput() async throws {
        let projectRoot = makeTempDir(prefix: "diag_agent")
        let runtime = try await makeRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        let fileName = "diag-test-\(UUID().uuidString).txt"
        let prompt = "Create a file named \(fileName) with the content 'hello diagnostics'. Use the create_file tool, then finish."
        let runId = UUID().uuidString

        await AIToolTraceLogger.shared.setProjectRoot(projectRoot)

        manager.currentInput = prompt
        manager.sendMessage()

        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 180)
        XCTAssertFalse(timedOut, "Diagnostics agent run timed out")

        printDiagnostics(manager: manager, runtime: runtime, prompt: prompt, runId: runId)

        // Verify tool execution
        let completedTools = manager.messages.filter { $0.isToolExecution && $0.toolStatus == .completed }
        let toolNames = completedTools.compactMap(\.toolName)
        XCTAssertTrue(
            toolNames.contains("create_file") || toolNames.contains("write_file"),
            "Expected create_file or write_file execution. Tools: \(toolNames)"
        )

        // Verify visible assistant output after tool execution
        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        XCTAssertFalse(assistantMessages.isEmpty, "Expected at least one assistant message after tool execution")

        let finalContent = assistantMessages.last?.content ?? ""
        let trimmedContent = finalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(
            trimmedContent.isEmpty,
            "Expected non-empty visible content after agent run. Got: '\(finalContent)'"
        )
        XCTAssertFalse(
            trimmedContent.contains("Assistant returned no user-visible response"),
            "Agent produced empty response — content was replaced by fallback."
        )
    }

    /// Send a chat-mode prompt and inspect reasoning extraction in detail.
    /// This test does NOT fail on empty content — it prints diagnostics so we can
    /// see exactly what the model returned and how splitReasoning handled it.
    func testDiagnosticsInspectReasoningExtraction() async throws {
        let projectRoot = makeTempDir(prefix: "diag_reasoning")
        let runtime = try await makeRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .chat

        let prompt = "Think step by step about what 2+2 equals, then give me the answer."
        let runId = UUID().uuidString

        await AIToolTraceLogger.shared.setProjectRoot(projectRoot)

        manager.currentInput = prompt
        manager.sendMessage()

        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 90)
        XCTAssertFalse(timedOut, "Diagnostics reasoning inspection timed out")

        printDiagnostics(manager: manager, runtime: runtime, prompt: prompt, runId: runId)

        // Inspect reasoning extraction in detail
        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        guard let lastAssistant = assistantMessages.last else {
            XCTFail("No assistant message produced")
            return
        }

        print("[DIAG] === Reasoning Extraction Analysis ===")
        print("[DIAG] ChatMessage.content (first 500 chars): \(String(lastAssistant.content.prefix(500)))")
        print("[DIAG] ChatMessage.reasoning: \(lastAssistant.reasoning ?? "nil")")

        let split = ChatPromptBuilder.splitReasoning(from: lastAssistant.content)
        print("[DIAG] splitReasoning.reasoning (first 300 chars): \(String((split.reasoning ?? "nil").prefix(300)))")
        print("[DIAG] splitReasoning.content (first 300 chars): \(String(split.content.prefix(300)))")

        let displayContent = ChatPromptBuilder.contentForDisplay(from: lastAssistant.content)
        print("[DIAG] contentForDisplay (first 300 chars): \(String(displayContent.prefix(300)))")

        let trimmedDisplay = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[DIAG] trimmed display content is empty: \(trimmedDisplay.isEmpty)")

        if trimmedDisplay.isEmpty {
            print("[DIAG] ⚠️  WARNING: Model produced no visible content after reasoning split!")
            print("[DIAG] ⚠️  This means the model's output was entirely consumed as reasoning.")
            print("[DIAG] ⚠️  Check if the model uses a reasoning format that splitTaggedReasoning doesn't recognize.")
        }
    }

    // MARK: - Private Helpers

    /// Verify that local model inference completes within a reasonable time budget.
    /// This catches regressions where local model requests get routed through the
    /// full orchestration graph (strategic planning, tactical planning, QA reviews)
    /// instead of the fast-path tool loop, causing massive overhead.
    func testDiagnosticsLocalInferencePerformanceBudget() async throws {
        let projectRoot = makeTempDir(prefix: "diag_perf")
        let runtime = try await makeRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .chat

        let prompt = "Reply with exactly one short greeting sentence and stop."
        await AIToolTraceLogger.shared.setProjectRoot(projectRoot)

        let startTime = ContinuousClock.now
        manager.currentInput = prompt
        manager.sendMessage()

        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 60)
        let elapsed = startTime.duration(to: ContinuousClock.now)

        XCTAssertFalse(timedOut, "Performance budget run timed out after 60s")

        let elapsedSeconds = elapsed.components.seconds
        print("[DIAG] Performance: completed in \(elapsedSeconds)s with model \(runtime.modelId)")

        // A simple greeting prompt should complete in under 30 seconds on local MLX.
        // If it takes longer, something is routing through unnecessary orchestration nodes.
        XCTAssertLessThan(
            elapsedSeconds, 30,
            "Local inference took \(elapsedSeconds)s — expected < 30s for a simple greeting. " +
            "Check if local model requests are being routed through the full orchestration graph " +
            "instead of the fast-path executeLocalModelToolLoop."
        )

        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        XCTAssertFalse(assistantMessages.isEmpty, "Expected at least one assistant message")
    }

    // MARK: - Private Helpers

    private struct Runtime {
        let manager: ConversationManager
        let modelId: String
    }

    private func makeTempDir(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func makeRuntime(projectRoot: URL?) async throws -> Runtime {
        let environment = ProcessInfo.processInfo.environment
        let testProfilePath = environment[TestLaunchKeys.testProfileDir]
            ?? environment["TEST_RUNNER_ENV_OSXIDE_TEST_PROFILE_DIR"]

        let container = DependencyContainer(
            launchContext: AppLaunchContext(
                mode: .unitTest,
                isTesting: true,
                isUITesting: false,
                testProfilePath: testProfilePath,
                disableHeavyInit: false,
                productionParityHarness: false
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
            toolPromptMode: currentSettings.toolPromptMode,
            ragEnabledDuringToolLoop: false
        ))

        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        container.settingsStore.set(true, forKey: "AI.OfflineModeEnabled")
        await selectionStore.setOfflineModeEnabled(true)

        let modelId = try await resolveModelId()
        container.settingsStore.set(modelId, forKey: "LocalModel.SelectedId")
        await selectionStore.setSelectedModelId(modelId)

        await LocalModelInferenceOverrides.shared.set(LocalModelInferenceOverrides(
            contextLength: 65536,
            maxKVSize: 8192,
            maxOutputTokens: 2048,
            prefillStepSize: 512,
            temperature: 0.35,
            topP: 0.92,
            repetitionPenalty: 1.03,
            repetitionContextSize: 64,
            kvCache4BitEnabled: true
        ))

        if let projectRoot {
            container.workspaceService.currentDirectory = projectRoot
            container.projectCoordinator.configureProject(root: projectRoot)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "LocalModelResponseDiagnosticsHarnessTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected conversation manager type"]
            )
        }

        manager.startNewConversation()
        manager.clearConversation()

        return Runtime(manager: manager, modelId: modelId)
    }

    private func resolveModelId() async throws -> String {
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

    private func waitForConversationToFinish(
        _ manager: ConversationManager,
        timeoutSeconds: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !manager.isSending { return false }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if !manager.isSending { return false }

        let recentMessages = manager.messages.suffix(8).map { msg in
            let tool = msg.toolName ?? "-"
            let status = msg.toolStatus?.rawValue ?? "-"
            return "\(msg.role.rawValue):\(tool):\(status): \(msg.content.prefix(200))"
        }
        print("[DIAG] ⚠️  TIMEOUT — recent messages:")
        for msg in recentMessages {
            print("[DIAG]   \(msg)")
        }
        return true
    }

    private func printDiagnostics(
        manager: ConversationManager,
        runtime: Runtime,
        prompt: String,
        runId: String
    ) {
        print("[DIAG] ============================================")
        print("[DIAG] Model: \(runtime.modelId)")
        print("[DIAG] Prompt: \(prompt.prefix(200))")
        print("[DIAG] Run ID: \(runId)")
        print("[DIAG] Total messages: \(manager.messages.count)")
        print("[DIAG] --------------------------------------------")

        for (index, msg) in manager.messages.enumerated() {
            let role = msg.role.rawValue
            let tool = msg.toolName ?? "-"
            let status = msg.toolStatus?.rawValue ?? "-"
            let contentPreview = msg.content.prefix(300).replacingOccurrences(of: "\n", with: "\\n")
            let reasoningPreview = (msg.reasoning ?? "nil").prefix(200).replacingOccurrences(of: "\n", with: "\\n")
            let hasToolCalls = msg.toolCalls != nil ? "yes(\(msg.toolCalls!.count))" : "no"
            print("[DIAG] [\(index)] \(role) tool=\(tool) status=\(status) toolCalls=\(hasToolCalls)")
            print("[DIAG]   content: \(contentPreview)")
            if msg.reasoning != nil {
                print("[DIAG]   reasoning: \(reasoningPreview)")
            }
        }

        print("[DIAG] --------------------------------------------")
        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        print("[DIAG] Non-draft assistant messages: \(assistantMessages.count)")

        if let last = assistantMessages.last {
            let split = ChatPromptBuilder.splitReasoning(from: last.content)
            let visibleContent = split.content.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[DIAG] Last assistant message visible content length: \(visibleContent.count)")
            print("[DIAG] Last assistant message has reasoning field: \(last.reasoning != nil)")
            print("[DIAG] splitReasoning found reasoning: \(split.reasoning != nil)")
            if visibleContent.isEmpty {
                print("[DIAG] ⚠️  VISIBLE CONTENT IS EMPTY — model produced only reasoning or no output")
            }
        }

        print("[DIAG] ============================================")
    }
}
