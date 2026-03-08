import XCTest
@testable import osx_ide

/// Dedicated offline harness tests.
/// These tests validate offline-specific behavior and should be run separately
/// from production-parity online harness suites.
@MainActor
final class OfflineModeHarnessTests: XCTestCase {
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
        try await finishOrCancelGeneration(manager, gracefulWaitSeconds: 5)

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
            minimumCount: 2,
            in: manager,
            timeoutSeconds: 45
        )
        try await finishOrCancelGeneration(manager, gracefulWaitSeconds: 8)

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

    func testOfflineHarnessCreateReactAppThroughMLX() async throws {
        let result = try await runOfflineScenarioUntilStable(
            name: "mlx_create_react_app",
            prepare: nil,
            prompt: """
                Create a simple React application structure using vite.
                1. Create package.json with react and react-dom dependencies
                2. Create index.html
                3. Create src/main.jsx
                4. Create src/App.jsx with a simple counter component
                Do not run npm install. Only create or edit files using tools, then finish.
                """,
            timeoutSeconds: 120
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
    }

    private struct ScenarioResult {
        let projectRoot: URL
        let manager: ConversationManager
        let telemetry: ToolExecutionTelemetrySummary
    }

    private func makeRuntime(offlineModeEnabled: Bool, projectRoot: URL? = nil) async throws -> Runtime {
        let container = DependencyContainer(
            launchContext: AppLaunchContext(
                mode: .unitTest,
                isTesting: true,
                isUITesting: false,
                testProfilePath: nil,
                disableHeavyInit: false
            )
        )

        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        await selectionStore.setOfflineModeEnabled(offlineModeEnabled)
        let effectiveOfflineMode = await selectionStore.isOfflineModeEnabled()
        XCTAssertEqual(effectiveOfflineMode, offlineModeEnabled)

        if let projectRoot {
            container.workspaceService.currentDirectory = projectRoot
            container.projectCoordinator.configureProject(root: projectRoot)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "OfflineModeHarnessTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected conversation manager type"]
            )
        }

        return Runtime(manager: manager)
    }

    private func runOfflineScenarioUntilStable(
        name: String,
        prepare: ((URL) throws -> Void)?,
        prompt: String,
        timeoutSeconds: TimeInterval
    ) async throws -> ScenarioResult {
        var lastResult: ScenarioResult?

        for attempt in 1...maxScenarioAttempts {
            let projectRoot = makeTempDir(prefix: name)
            try prepare?(projectRoot)

            ToolExecutionTelemetry.shared.reset()
            let runtime = try await makeRuntime(offlineModeEnabled: true, projectRoot: projectRoot)
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
        XCTFail("Timed out waiting for conversation manager to finish send task")
        return true
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
        minimumCount: Int,
        in manager: ConversationManager,
        timeoutSeconds: TimeInterval
    ) async throws -> [ChatMessage] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let completedMessages = manager.messages.filter {
                $0.isToolExecution && $0.toolStatus == .completed
            }
            if completedMessages.count >= minimumCount {
                return completedMessages
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("Timed out waiting for local MLX agent to complete at least \(minimumCount) tool executions")
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
            if !relative.hasPrefix(".ide") {
                files.append(relative)
            }
        }
        return files.sorted()
    }
}
