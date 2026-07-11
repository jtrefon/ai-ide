import XCTest
@testable import osx_ide

/// Harness test that sends prompts through the full local model pipeline with
/// timestamped logging at every step to identify performance bottlenecks.
///
/// Run with:
///   ./run.sh harness InferenceTimingHarnessTests
///
/// Or specific test:
///   ./run.sh harness InferenceTimingHarnessTests/testInferenceTimingSimple
///
/// Environment overrides:
///   HARNESS_MODEL_ID - model ID to use (default: first installed model)
@MainActor
final class InferenceTimingHarnessTests: XCTestCase {
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

    /// Send a simple prompt and measure total response time with timestamped logging.
    /// Target: < 5s on M4 16GB with 4B quantized model.
    func testInferenceTimingSimple() async throws {
        let ts = TimestampLogger(label: "TIMING")
        ts.log("=== Starting inference timing test ===")

        ts.log("Step 1: Setting up runtime")
        let projectRoot = makeTempDir(prefix: "timing_simple")
        let runtime = try await makeRuntime(projectRoot: projectRoot, ts: ts)
        let manager = runtime.manager
        manager.currentMode = .chat
        ts.log("  Runtime ready, model: \(runtime.modelId)")

        ts.log("Step 2: Sending prompt")
        let prompt = "Reply with exactly one short greeting sentence and stop."
        manager.currentInput = prompt
        manager.sendMessage()

        ts.log("Step 3: Waiting for response (timeout 60s)")
        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 60, ts: ts)
        let totalSeconds = ts.elapsedSeconds()

        ts.log("Step 4: Checking results")
        XCTAssertFalse(timedOut, "Inference timed out after 60s")

        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        let responseContent = assistantMessages.last?.content ?? ""
        ts.log("  Response: '\(responseContent.prefix(200))'")
        ts.log("  Messages: \(manager.messages.count)")
        ts.log("  Total time: \(totalSeconds)s")

        ts.log("=== RESULT: \(totalSeconds)s (target: < 5s) ===")

        if totalSeconds >= 5 {
            ts.log("⚠️ SLOW: Generation took \(totalSeconds)s — target is < 5s")
            printAllTimestamps()
        }

        XCTAssertFalse(
            responseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Expected non-empty response"
        )
        XCTAssertLessThan(
            Int(totalSeconds), 30,
            "Inference took \(totalSeconds)s — expected < 30s. Check timestamps above."
        )
    }

    /// Second prompt on the same runtime — model should be warm.
    func testInferenceTimingWarmModel() async throws {
        let ts = TimestampLogger(label: "TIMING-WARM")
        ts.log("=== Starting warm model timing test ===")

        let projectRoot = makeTempDir(prefix: "timing_warm")
        let runtime = try await makeRuntime(projectRoot: projectRoot, ts: ts)
        let manager = runtime.manager
        manager.currentMode = .chat

        // First prompt (cold)
        ts.log("First prompt (cold model)")
        manager.currentInput = "Say hello."
        manager.sendMessage()
        let coldTimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 60, ts: ts)
        let coldSeconds = ts.elapsedSeconds()
        XCTAssertFalse(coldTimedOut, "Cold inference timed out")
        ts.log("  Cold response in \(coldSeconds)s")

        // Reset for second prompt
        ts.log("Second prompt (warm model)")
        ts.reset()
        manager.startNewConversation()
        manager.currentInput = "Say goodbye."
        manager.sendMessage()
        let warmTimedOut = try await waitForConversationToFinish(manager, timeoutSeconds: 60, ts: ts)
        let warmSeconds = ts.elapsedSeconds()
        XCTAssertFalse(warmTimedOut, "Warm inference timed out")

        let assistantMessages = manager.messages.filter { $0.role == .assistant && !$0.isDraft }
        ts.log("  Warm response: '\(assistantMessages.last?.content.prefix(200) ?? "(empty)")'")
        ts.log("  Warm time: \(warmSeconds)s")
        ts.log("=== RESULT: Cold=\(coldSeconds)s Warm=\(warmSeconds)s (target: < 5s) ===")

        XCTAssertLessThan(
            Int(warmSeconds), 30,
            "Warm inference took \(warmSeconds)s — expected < 30s."
        )
    }

    // MARK: - Helpers

    private func makeTempDir(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func makeRuntime(projectRoot: URL, ts: TimestampLogger) async throws -> Runtime {
        ts.log("  makeRuntime: creating DependencyContainer")
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

        ts.log("  makeRuntime: configuring offline mode")
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
        container.settingsStore.set(true, forKey: "AI.OfflineModeEnabled")
        await selectionStore.setOfflineModeEnabled(true)

        let modelId = try await resolveModelId()
        ts.log("  makeRuntime: model resolved: \(modelId)")
        container.settingsStore.set(modelId, forKey: "LocalModel.SelectedId")
        await selectionStore.setSelectedModelId(modelId)

        ts.log("  makeRuntime: setting inference overrides")
        await LocalModelInferenceOverrides.shared.set(LocalModelInferenceOverrides(
            contextLength: 8192,
            maxKVSize: 4096,
            maxOutputTokens: 128,
            prefillStepSize: 512,
            temperature: 0.35,
            topP: 0.92,
            repetitionPenalty: 1.03,
            repetitionContextSize: 64,
            kvCache4BitEnabled: true
        ))

        ts.log("  makeRuntime: configuring project")
        container.workspaceService.currentDirectory = projectRoot
        container.projectCoordinator.configureProject(root: projectRoot)
        try await Task.sleep(nanoseconds: 500_000_000)

        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "InferenceTimingHarnessTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected conversation manager type"]
            )
        }

        manager.startNewConversation()
        manager.clearConversation()
        ts.log("  makeRuntime: done")
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
        timeoutSeconds: TimeInterval,
        ts: TimestampLogger
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastPollElapsed = 0
        while Date() < deadline {
            if !manager.isSending { return false }
            let elapsed = ts.elapsedSeconds()
            if elapsed - lastPollElapsed >= 5 {
                ts.log("  ... still waiting (\(elapsed)s elapsed)")
                lastPollElapsed = elapsed
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if !manager.isSending { return false }

        ts.log("  ⚠️ TIMEOUT after \(timeoutSeconds)s")
        let recentMessages = manager.messages.suffix(8).map { msg in
            let tool = msg.toolName ?? "-"
            let status = msg.toolStatus?.rawValue ?? "-"
            return "\(msg.role.rawValue):\(tool):\(status): \(msg.content.prefix(200))"
        }
        for msg in recentMessages {
            ts.log("  \(msg)")
        }
        return true
    }

    private func printAllTimestamps() {
        // The TimestampLogger already prints in real-time via stdout
        // This is a hook for additional post-hoc analysis if needed
    }

    private struct Runtime {
        let manager: ConversationManager
        let modelId: String
    }
}

// MARK: - TimestampLogger

private final class TimestampLogger {
    private let label: String
    private var startTime: ContinuousClock.Instant

    init(label: String) {
        self.label = label
        self.startTime = ContinuousClock.now
    }

    func log(_ message: String) {
        let elapsed = startTime.duration(to: ContinuousClock.now)
        let ms = Self.ms(elapsed)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(label)] [\(timestamp)] [+\(ms)ms] \(message)")
        fflush(stdout)
    }

    func reset() {
        startTime = ContinuousClock.now
    }

    func elapsedSeconds() -> Int {
        Int(Self.ms(startTime.duration(to: ContinuousClock.now)) / 1000)
    }

    static func ms(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
