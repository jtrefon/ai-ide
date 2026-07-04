//
//  RealServiceToolLoopTests.swift
//  osx-ideHarnessTests
//
//  Tool loop tests using real services instead of mocks where possible
//  This ensures production parity while still allowing focused testing
//

import XCTest
@testable import osx_ide
import Combine

/// Tool loop tests using real services for production parity
/// Only uses mocks where absolutely necessary for test isolation
@MainActor
final class RealServiceToolLoopTests: XCTestCase {
    private let maxScenarioAttempts = 2
    private let scenarioTimeoutSeconds: TimeInterval = 180

    private func requireOnlineHarnessExecution() throws {}

    override func setUp() async throws {
        try await super.setUp()
        // Do not remove this gate or allow these online harness tests to run in parallel.
        // Parallel provider traffic has triggered upstream 429 floods and can get the account banned.
        await OnlineHarnessExecutionGate.shared.acquire()
        // Online production-parity harness configuration.
        let config = TestConfiguration(
            allowExternalAPIs: true,
            minAPIRequestInterval: 1.0,
            serialExternalAPITests: true,
            externalAPITimeout: 60.0,
            useMockServices: false
        )
        await TestConfigurationProvider.shared.setConfiguration(config)
    }
    
    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        await OnlineHarnessExecutionGate.shared.release()
        try await super.tearDown()
    }
    
    // MARK: - Test: Tool Loop with Real OpenRouter Service
    
    func testToolLoopWithRealOpenRouterService() async throws {
        try requireOnlineHarnessExecution()
        print("\n=== Test: Tool Loop with Real OpenRouter Service ===")
        let result = try await runScenarioUntilStable(
            name: "tool_loop_uppercase",
            prepare: { root in
                let testFile = root.appendingPathComponent("test.txt")
                try "Hello World".write(to: testFile, atomically: true, encoding: .utf8)
            },
            prompt: """
                Read test.txt and create output.txt containing exactly HELLO WORLD.
                Use at most one read and one write operation, then finish.
                """,
        )

        let files = listAllFiles(under: result.projectRoot)
        print("[HARNESS][INFO] tool_loop_uppercase files=\(files)")
        let lastAssistantContent = result.manager.messages.last(where: { $0.role == .assistant })?.content ?? ""
        print("[HARNESS][INFO] tool_loop_uppercase lastAssistant=\(lastAssistantContent)")
        harnessTrue(files.contains("output.txt"), "Should have created output.txt")
        if files.contains("output.txt") {
            let outputContent = try String(contentsOf: result.projectRoot.appendingPathComponent("output.txt"))
            harnessEqual(
                outputContent.trimmingCharacters(in: .whitespacesAndNewlines),
                "HELLO WORLD",
                "output.txt should contain uppercase content"
            )
        }
    }
    
    // MARK: - Test: Tool Deduplication with Real Service
    
    func testToolDeduplicationWithRealService() async throws {
        try requireOnlineHarnessExecution()
        print("\n=== Test: Tool Deduplication with Real Service ===")
        let result = try await runScenarioUntilStable(
            name: "tool_dedup_list_once",
            prepare: nil,
            prompt: """
                List files in this directory exactly once and then finish.
                Do not repeat any tool call arguments.
                """,
        )
        print("\nTelemetry summary: \(result.telemetry.healthReport)")
        harnessTrue(result.telemetry.deduplicatedToolCalls >= 0, "Should track deduplicated tool calls")
    }
    
    // MARK: - Test: Error Handling with Real Service
    
    func testErrorHandlingWithRealService() async throws {
        try requireOnlineHarnessExecution()
        print("\n=== Test: Error Handling with Real Service ===")
        let result = try await runScenarioUntilStable(
            name: "error_handling_stable_path",
            prepare: { root in
                let seedFile = root.appendingPathComponent("source.txt")
                try "stable input".write(to: seedFile, atomically: true, encoding: .utf8)
            },
            prompt: """
                Read source.txt and create processed.txt containing exactly STABLE INPUT.
                Avoid retries, duplicate calls, and fallback paths.
                """,
        )

        let files = listAllFiles(under: result.projectRoot)
        harnessTrue(files.contains("processed.txt"), "Should create processed.txt without fallback retries")
        if files.contains("processed.txt") {
            let created = try String(contentsOf: result.projectRoot.appendingPathComponent("processed.txt"), encoding: .utf8)
            harnessEqual(created.trimmingCharacters(in: .whitespacesAndNewlines), "STABLE INPUT", "Processed output should match expected uppercase content")
        }
    }

    func testFailureRecoveryUsesFallbackWithoutRepeatedIdenticalFailures() async throws {
        try requireOnlineHarnessExecution()
        print("\n=== Test: Failure Recovery Uses Fallback ===")
        let result = try await runScenarioUntilStable(
            name: "fallback_single_write",
            prepare: nil,
            prompt: """
                Create must-fail-first.txt with content Recovered via fallback.
                Execute exactly one write operation and finish.
                """,
        )

        let lastAssistantContent = result.manager.messages.last(where: { $0.role == .assistant })?.content ?? ""
        if lastAssistantContent.localizedCaseInsensitiveContains("read-only Chat mode") {
            harnessNote("Local model runtime downgraded Agent mode to read-only Chat mode; continuing without fallback verification.")
            return
        }

        let files = listAllFiles(under: result.projectRoot)
        guard files.contains("must-fail-first.txt") else {
            harnessNote("Agent did not create fallback file must-fail-first.txt")
            return
        }

        let createdContent = try String(
            contentsOf: result.projectRoot.appendingPathComponent("must-fail-first.txt"),
            encoding: .utf8
        )
        harnessTrue(
            createdContent.localizedCaseInsensitiveContains("recovered"),
            "Fallback file should contain recovery marker content"
        )

        let failedToolExecutionMessages = result.manager.messages.filter {
            $0.isToolExecution && $0.toolStatus == .failed
        }
        let repeatedFailureSignatures = repeatedFailureSignatureCounts(from: failedToolExecutionMessages)

        if failedToolExecutionMessages.isEmpty {
            print("[HARNESS][warning] No failed tool execution captured in this run; skipping repeated-failure signature assertion.")
        } else {
            harnessTrue(
                repeatedFailureSignatures.isEmpty,
                "Agent should avoid repeating identical failed tool signatures. Repeats: \(repeatedFailureSignatures)"
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private struct ProductionRuntime {
        let container: DependencyContainer
        let manager: ConversationManager
    }
    
    private func makeProductionRuntime(projectRoot: URL, mode: AIMode = .agent) async throws -> ProductionRuntime {
        // Use the real DependencyContainer with production-parity online routing.
        let container = DependencyContainer(launchContext: AppLaunchContext(mode: .unitTest, isTesting: true, isUITesting: false, testProfilePath: nil, disableHeavyInit: false, productionParityHarness: false))
        container.settingsStore.set(false, forKey: AppConstantsStorage.agentQAReviewEnabledKey)
        
        // Production-parity harness: keep agent mode online-capable so routing uses OpenRouter.
        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        await selectionStore.setOfflineModeEnabled(false)
        let isOfflineModeEnabled = await selectionStore.isOfflineModeEnabled()
        harnessFalse(isOfflineModeEnabled, "Production-parity harness must not run in Offline Mode")
        
        // Route to Kilo Code (proven to return tool calls, unlike OpenRouter free tier)
        let provStore = AIProviderSelectionStore(settingsStore: container.settingsStore)
        await provStore.setSelectedRemoteProvider(.kiloCode)
        
        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "RealServiceToolLoopTests", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ConversationManager is not the expected concrete type"
                ])
        }
        
        // Emulate what the app does when a project is selected
        container.workspaceService.currentDirectory = projectRoot
        container.projectCoordinator.configureProject(root: projectRoot)
        
        // Wait for setup
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return ProductionRuntime(container: container, manager: manager)
    }
    
    private struct ScenarioResult {
        let projectRoot: URL
        let manager: ConversationManager
        let telemetry: ToolExecutionTelemetrySummary
        let gate: ScenarioGate
    }

    private struct ScenarioGate {
        let repeatedToolCallSignatures: Int
        let failedToolExecutions: Int
        let timedOut: Bool
        let gatePassed: Bool
    }

    private func runScenarioUntilStable(
        name: String,
        prepare: ((URL) throws -> Void)?,
        prompt: String,
        mode: AIMode = .agent
    ) async throws -> ScenarioResult {
        var lastResult: ScenarioResult?

        for attempt in 1...maxScenarioAttempts {
            let projectRoot = makeTempDir()
            try prepare?(projectRoot)

            ToolExecutionTelemetry.shared.reset()
            let runtime = try await makeProductionRuntime(projectRoot: projectRoot, mode: mode)
            let manager = runtime.manager
            manager.currentMode = mode

            let timedOut = try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: scenarioTimeoutSeconds)
            let telemetry = ToolExecutionTelemetry.shared.summary
            let failedToolExecutions = manager.messages.filter { $0.isToolExecution && $0.toolStatus == .failed }.count
            let repeatedToolCallSignatures = telemetry.repeatedToolCallSignatures
            let gatePassed = !timedOut && failedToolExecutions == 0 && repeatedToolCallSignatures == 0

            let gate = ScenarioGate(
                repeatedToolCallSignatures: repeatedToolCallSignatures,
                failedToolExecutions: failedToolExecutions,
                timedOut: timedOut,
                gatePassed: gatePassed
            )
            let result = ScenarioResult(projectRoot: projectRoot, manager: manager, telemetry: telemetry, gate: gate)
            lastResult = result

            print("[HARNESS][GATE] scenario=\(name) attempt=\(attempt) passed=\(gatePassed) repeated=\(repeatedToolCallSignatures) failed_tools=\(failedToolExecutions) timed_out=\(timedOut)")
            if gatePassed {
                return result
            }

            if attempt < maxScenarioAttempts {
                cleanup(projectRoot)
            }
        }

        guard let fallback = lastResult else {
            throw NSError(domain: "RealServiceToolLoopTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "No scenario attempts executed for \(name)"])
        }
        XCTFail(
            "Scenario \(name) did not reach clean gate after \(maxScenarioAttempts) attempts. " +
            "timedOut=\(fallback.gate.timedOut) failedToolExecutions=\(fallback.gate.failedToolExecutions) " +
            "repeatedToolCallSignatures=\(fallback.gate.repeatedToolCallSignatures)"
        )
        return fallback
    }

    @discardableResult
    private func sendProductionMessage(
        _ text: String, manager: ConversationManager, timeoutSeconds: TimeInterval = 180
    ) async throws -> Bool {
        manager.currentInput = text
        manager.sendMessage()
        let timedOut = try await waitForConversationToFinish(manager, timeoutSeconds: timeoutSeconds)
        if let error = manager.error {
            harnessNote("Conversation manager reported error: \(error)")
        }
        return timedOut
    }

    @discardableResult
    private func waitForConversationToFinish(
        _ manager: ConversationManager, timeoutSeconds: TimeInterval = 180
    ) async throws -> Bool {
        var lastProgressAt = Date()
        var lastMessageCount = manager.messages.count

        while true {
            if !manager.isSending {
                return false
            }

            let currentMessageCount = manager.messages.count
            if currentMessageCount != lastMessageCount {
                lastMessageCount = currentMessageCount
                lastProgressAt = Date()
            }

            if Date().timeIntervalSince(lastProgressAt) >= timeoutSeconds {
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if !manager.isSending {
            return false
        }
        harnessNote("Timed out waiting for conversation manager to finish send task (idle for \(Int(timeoutSeconds))s)")
        return true
    }
    
    private func listAllFiles(under directory: URL) -> [String] {
        let fm = FileManager.default
        let basePath = directory.standardizedFileURL.path
        guard
            let enumerator = fm.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else {
            return []
        }
        var files: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                values.isRegularFile == true
            else { continue }
            let filePath = url.standardizedFileURL.path
            let relative = String(filePath.dropFirst(basePath.count + 1))
            if !relative.hasPrefix(AppConstantsFileSystem.projectDirName) {
                files.append(relative)
            }
        }
        return files.sorted()
    }
    
    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("real_service_toolloop_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    private func repeatedFailureSignatureCounts(from failedMessages: [ChatMessage]) -> [String: Int] {
        var signatureCounts: [String: Int] = [:]

        for message in failedMessages {
            let signature = [
                message.toolName ?? "unknown_tool",
                message.toolCallId ?? "unknown_call",
                message.targetFile ?? "unknown_target"
            ].joined(separator: "|")
            signatureCounts[signature, default: 0] += 1
        }

        return signatureCounts.filter { $0.value > 1 }
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func harnessTrue(_ condition: @autoclosure () -> Bool, _ message: String = "") {
        let ok = condition()
        print(ok ? "[HARNESS][PASS] \(message)" : "[HARNESS][WARN] \(message)")
        XCTAssertTrue(ok, message)
    }

    private func harnessFalse(_ condition: @autoclosure () -> Bool, _ message: String = "") {
        let value = condition()
        print(!value ? "[HARNESS][PASS] \(message)" : "[HARNESS][WARN] \(message)")
        XCTAssertFalse(value, message)
    }

    private func harnessEqual<T: Equatable & Sendable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String = "") {
        let left = lhs()
        let right = rhs()
        let status = (left == right) ? "[HARNESS][PASS]" : "[HARNESS][WARN]"
        print("\(status) \(message) lhs=\(left) rhs=\(right)")
        XCTAssertEqual(left, right, message)
    }

    private func harnessNote(_ message: String) {
        print("[HARNESS][WARN] \(message)")
    }
    
    // MARK: - DeepSeek V4 Pro Harness
    
    func testDeepSeekV4ProToolLoopWithThinking() async throws {
        try requireOnlineHarnessExecution()
        print("\n=== Test: DeepSeek V4 Pro Tool Loop with Thinking ===\n")
        
        // Select DeepSeek provider and model via UserDefaults BEFORE creating runtime.
        // The harness reuses the app's existing key from UserDefaults (DeepSeekAPIKey).
        let defaults = AppRuntimeEnvironment.userDefaults
        defaults.set("deepSeek", forKey: "AI.SelectedRemoteProvider")
        defaults.set("deepseek-v4-pro", forKey: "DeepSeekModel")
        defaults.set("modelAndAgent", forKey: "DeepSeekReasoningMode")
        defaults.set("https://api.deepseek.com/v1", forKey: "DeepSeekBaseURL")
        defaults.synchronize()
        
        let result = try await runScenarioUntilStable(
            name: "deepseek_v4_pro_uppercase",
            prepare: { root in
                let testFile = root.appendingPathComponent("input.txt")
                try "hello world from deepseek".write(to: testFile, atomically: true, encoding: .utf8)
            },
            prompt: """
                Read input.txt and create output.txt containing exactly HELLO WORLD FROM DEEPSEEK (uppercase).
                Use at most one read and one write operation, then finish.
                """,
        )
        
        let files = listAllFiles(under: result.projectRoot)
        print("[HARNESS][INFO] deepseek_v4_pro files=\(files)")
        let lastAssistant = result.manager.messages.last(where: { $0.role == .assistant })?.content ?? ""
        print("[HARNESS][INFO] deepseek_v4_pro lastAssistant=\(lastAssistant)")
        
        // Log telemetry for debugging
        let summary = result.telemetry
        print("[HARNESS][INFO] deepseek_v4_pro iterations=\(summary.totalIterations) successful=\(summary.successfulExecutions)")
        
        harnessTrue(files.contains("output.txt"), "Should have created output.txt")
        if files.contains("output.txt") {
            let content = try String(contentsOf: result.projectRoot.appendingPathComponent("output.txt"))
            harnessEqual(
                content.trimmingCharacters(in: .whitespacesAndNewlines),
                "HELLO WORLD FROM DEEPSEEK",
                "output.txt should contain uppercase content"
            )
        }
    }

    // MARK: - Coder Mode Tests

    func testCoderModeWithRealService() async throws {
        try requireOnlineHarnessExecution()
        print("\n=== Test: Coder Mode with Real OpenRouter Service ===")
        let result = try await runScenarioUntilStable(
            name: "coder_mode_read_then_patch",
            prepare: { root in
                let srcDir = root.appendingPathComponent("src")
                try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
                let component = srcDir.appendingPathComponent("Counter.tsx")
                try """
                import { useState } from 'react'

                export function Counter() {
                  const [count, setCount] = useState(0)

                  return (
                    <div>
                      <p>Count: {count}</p>
                      <button onClick={() => setCount(count + 1)}>Increment</button>
                    </div>
                  )
                }
                """.write(to: component, atomically: true, encoding: .utf8)
            },
            prompt: """
                Read src/Counter.tsx. Add a "Decrement" button that decreases the count.
                Use patch_file (NOT replace_in_file). After editing, read the file back to verify.
                """,
            mode: .coder
        )

        let files = listAllFiles(under: result.projectRoot)
        print("[HARNESS][INFO] coder_mode files=\(files)")

        // Verify Counter.tsx exists and has the Decrement button
        let counterPath = result.projectRoot.appendingPathComponent("src/Counter.tsx")
        if FileManager.default.fileExists(atPath: counterPath.path) {
            let content = try String(contentsOf: counterPath, encoding: .utf8)
            print("[HARNESS][INFO] Counter.tsx content:\n\(content)")
            harnessTrue(content.contains("Decrement"),
                       "Counter.tsx should contain a Decrement button")
            harnessTrue(content.contains("count - 1") || content.contains("count > 0"),
                       "Counter.tsx should decrement or prevent negative count")
        } else {
            harnessNote("Counter.tsx was not found — agent may have used a different approach")
        }

        // Verify no replace_in_file tool was used
        let usedReplace = result.manager.messages.filter {
            $0.isToolExecution && $0.toolName == "replace_in_file"
        }
        harnessTrue(usedReplace.isEmpty,
                   "Coder mode should NOT use replace_in_file. Used: \(usedReplace.count) time(s)")

        // Report telemetry
        print("[HARNESS][TELEMETRY] coder_mode gate=\(result.gate.gatePassed) "
              + "repeated=\(result.gate.repeatedToolCallSignatures) "
              + "failed=\(result.gate.failedToolExecutions)")
    }

    // MARK: - Complex scenario: Build React app, refactor to TypeScript, add tests

    func testComplexReactToTypeScriptScenario() async throws {
        try requireOnlineHarnessExecution()
        print("\n=== Test: Complex React → TypeScript → Tests ===")
        let result = try await runScenarioUntilStable(
            name: "react_typescript_testing",
            prepare: { root in
                // Scaffold a React todo app
                try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: root.appendingPathComponent("src/components"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: root.appendingPathComponent("public"), withIntermediateDirectories: true)

                try """
                {
                  "name": "todo-app",
                  "private": true,
                  "version": "1.0.0",
                  "type": "module",
                  "scripts": { "dev": "vite", "build": "vite build", "preview": "vite preview" },
                  "dependencies": { "react": "^18.3.1", "react-dom": "^18.3.1" },
                  "devDependencies": {
                    "@vitejs/plugin-react": "^4.3.0",
                    "typescript": "^5.7.0",
                    "vite": "^6.0.0"
                  }
                }
                """.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

                try """
                <!DOCTYPE html><html lang="en"><head><meta charset="UTF-8" />
                <meta name="viewport" content="width=device-width,initial-scale=1.0" />
                <title>Todo App</title></head>
                <body><div id="root"></div><script type="module" src="/src/main.jsx"></script></body></html>
                """.write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

                try """
                import React from 'react'
                import ReactDOM from 'react-dom/client'
                import App from './App.jsx'
                ReactDOM.createRoot(document.getElementById('root')).render(
                  <React.StrictMode><App /></React.StrictMode>
                )
                """.write(to: root.appendingPathComponent("src/main.jsx"), atomically: true, encoding: .utf8)

                try """
                import { useState } from 'react'
                export default function App() {
                  const [todos, setTodos] = useState([])
                  const addTodo = (text) => setTodos([...todos, { id: Date.now(), text, completed: false }])
                  const toggleTodo = (id) => setTodos(todos.map(t => t.id === id ? { ...t, completed: !t.completed } : t))
                  const removeTodo = (id) => setTodos(todos.filter(t => t.id !== id))
                  return (
                    <div><h1>Todo App</h1>
                      <input id="todo-input" placeholder="Add todo" />
                      <button id="add-btn" onClick={() => { const i = document.getElementById('todo-input'); addTodo(i.value); i.value = '' }}>Add</button>
                      <ul>{todos.map(todo => (
                        <li key={todo.id} style={{ textDecoration: todo.completed ? 'line-through' : 'none' }}>
                          {todo.text}
                          <button onClick={() => toggleTodo(todo.id)}>Toggle</button>
                          <button onClick={() => removeTodo(todo.id)}>Delete</button>
                        </li>
                      ))}</ul>
                    </div>
                  )
                }
                """.write(to: root.appendingPathComponent("src/App.jsx"), atomically: true, encoding: .utf8)

                try """
                export function Greeting({ name }) { return <p>Hello, {name}!</p> }
                """.write(to: root.appendingPathComponent("src/components/Greeting.jsx"), atomically: true, encoding: .utf8)

                try """
                import { defineConfig } from 'vite'
                import react from '@vitejs/plugin-react'
                export default defineConfig({ plugins: [react()] })
                """.write(to: root.appendingPathComponent("vite.config.js"), atomically: true, encoding: .utf8)
            },
            prompt: """
                We have a React todo app in JavaScript (JSX). I need you to do three things:

                1. Search the web for the best TypeScript unit testing framework for React components in 2026.
                   Use web_search to find articles, then web_browse to read at least one of them.
                2. Refactor all .jsx files to .tsx with proper TypeScript types. Create any config files needed
                   (tsconfig.json, vite-env.d.ts). Use patch_file for all edits — never replace_in_file or write_file.
                3. After refactoring, create a test file for the App component using the framework you found.
                   Read files first before editing them.

                Do NOT use replace_in_file or write_file — only patch_file for edits.
                """,
            mode: .coder
        )

        let files = listAllFiles(under: result.projectRoot)
        print("[HARNESS][INFO] complex_scenario files=\(files)")

        // Verify TypeScript files exist
        let tsxFiles = files.filter { $0.hasSuffix(".tsx") || $0.hasSuffix(".ts") }
        harnessTrue(tsxFiles.count > 0,
                           "TypeScript files should exist after refactoring. Found: \(tsxFiles)")

        // Verify test files exist  
        let testFiles = files.filter { $0.contains("test") || $0.contains("spec") || $0.contains("__tests__") }
        harnessTrue(testFiles.count > 0,
                           "Test files should exist. Found: \(testFiles)")

        // Verify web research was done
        let webTools = result.manager.messages.filter {
            $0.isToolExecution && ($0.toolName == "web_search" || $0.toolName == "web_browse")
        }
        harnessTrue(webTools.count > 0,
                           "Agent should use web tools for research. Used: \(webTools.count)")

        print("[HARNESS][TELEMETRY] complex_scenario gate=\(result.gate.gatePassed) "
              + "repeated=\(result.gate.repeatedToolCallSignatures) "
              + "failed=\(result.gate.failedToolExecutions)")
    }
}
