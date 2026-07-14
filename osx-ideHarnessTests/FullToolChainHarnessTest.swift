import XCTest
@testable import osx_ide

/// Full tool chain test via the REAL production ConversationManager path.
///
/// Uses the actual app DI container, real model router, and ToolLoopHandler.
/// The harness NEVER implements tool logic — only sends prompts and reads telemetry.
///
/// Provider is set to Kilo Code (not OpenRouter) because Kilo Code returns tool calls.
@MainActor
final class FullToolChainHarnessTest: XCTestCase {
    var tmpDir: URL!
    var container: DependencyContainer!
    var manager: ConversationManager!

    override func setUp() async throws {
        try await super.setUp()
        await OnlineHarnessExecutionGate.shared.acquire()
        let config = TestConfiguration(allowExternalAPIs: true, minAPIRequestInterval: 1.0,
            serialExternalAPITests: true, externalAPITimeout: 300.0, useMockServices: false)
        await TestConfigurationProvider.shared.setConfiguration(config)

        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("ftc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        container = DependencyContainer(
            launchContext: AppLaunchContext(mode: .unitTest, isTesting: true, isUITesting: false,
                testProfilePath: nil, disableHeavyInit: false, productionParityHarness: false))
        container.settingsStore.set(false, forKey: AppConstantsStorage.agentQAReviewEnabledKey)
        container.workspaceService.currentDirectory = tmpDir
        container.projectCoordinator.configureProject(root: tmpDir)

        guard let cm = container.conversationManager as? ConversationManager else {
            XCTFail("Not ConversationManager"); return
        }
        manager = cm

        // Route to Kilo Code
        let provStore = AIProviderSelectionStore()
        await provStore.setSelectedRemoteProvider(.kiloCode)
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        await TestConfigurationProvider.shared.resetToDefault()
        await OnlineHarnessExecutionGate.shared.release()
        try await super.tearDown()
    }

    func testReadFileTool() async throws {
        try "Hello World".write(to: tmpDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        manager.currentMode = .coder
        print("[HARNESS] Test: read_file + list_files")
        let timedOut = try await send("List the files and read readme.txt")
        XCTAssertFalse(timedOut, "Should complete without timeout")
        print("[HARNESS] Messages (\(manager.messages.count)):")
        for (i, msg) in manager.messages.enumerated() {
            let role = msg.role
            let tool = msg.toolName ?? ""
            let content = msg.content.prefix(200)
            let isTool = msg.isToolExecution
            print("[HARNESS]   [\(i)] \(role) tool=\(tool) isTool=\(isTool) \(content)")
        }
        let tools = extractToolCalls(from: manager.messages)
        print("[HARNESS] Tools used: \(tools)")
        XCTAssertTrue(tools.contains("read_file") || tools.contains("view_file") || tools.contains("list_files") || tools.contains("list_dir"),
            "Should call read_file or list_files. Called: \(tools)")
    }

    func testWriteFileTool() async throws {
        manager.currentMode = .coder
        print("[HARNESS] Test: write_file")
        let timedOut = try await send("Create a file called hello.js with content: console.log('hello')")
        XCTAssertFalse(timedOut, "Should complete without timeout")
        let tools = extractToolCalls(from: manager.messages)
        print("[HARNESS] Tools used: \(tools)")
        if FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("hello.js").path) {
            print("[HARNESS] ✅ hello.js was created")
        }
    }

    func testPatchFileTool() async throws {
        try "Line1\nLine2\nLine3".write(to: tmpDir.appendingPathComponent("greeting.txt"), atomically: true, encoding: .utf8)
        manager.currentMode = .coder
        print("[HARNESS] Test: patch_file")
        let timedOut = try await send("Read greeting.txt then change Line2 to CHANGED")
        XCTAssertFalse(timedOut, "Should complete without timeout")
        let tools = extractToolCalls(from: manager.messages)
        print("[HARNESS] Tools used: \(tools)")
    }

    func testWebSearchTool() async throws {
        manager.currentMode = .coder
        print("[HARNESS] Test: web_search")
        let timedOut = try await send("Search the web for 'Swift concurrency best practices 2026' and summarize")
        XCTAssertFalse(timedOut, "Should complete without timeout")
        let tools = extractToolCalls(from: manager.messages)
        print("[HARNESS] Tools used: \(tools)")
    }

    func testSearchProjectTool() async throws {
        try "function add(a,b) { return a + b }".write(to: tmpDir.appendingPathComponent("math.js"), atomically: true, encoding: .utf8)
        container.projectCoordinator.configureProject(root: tmpDir)
        manager.currentMode = .coder
        print("[HARNESS] Test: search_project")
        let timedOut = try await send("Search the project for files containing 'function'")
        XCTAssertFalse(timedOut, "Should complete without timeout")
        let tools = extractToolCalls(from: manager.messages)
        print("[HARNESS] Tools used: \(tools)")
    }

    func testMultiToolReadPatchVerify() async throws {
        try "Line1\nLine2\nLine3".write(to: tmpDir.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
        manager.currentMode = .coder
        print("[HARNESS] Test: read → patch → verify cycle")
        let timedOut = try await send("Read test.txt, change Line2 to CHANGED, then verify by reading the file again")
        XCTAssertFalse(timedOut, "Should complete without timeout")
        let tools = extractToolCalls(from: manager.messages)
        print("[HARNESS] Tools used: \(tools)")
    }

    /// Regression test for the immutable-context bug: in `.chat` mode the agent
    /// investigates (read-only) and proposes an architecture. Finalization must
    /// never wipe the streamed answer and replace it with the deterministic
    /// "I could not complete this task" fallback.
    func testChatModeFinalAnswerNotWiped() async throws {
        manager.currentMode = .chat
        print("[HARNESS] Test: chat mode final answer preservation")
        let timedOut = try await send("Explore this project and propose a proper architecture for adding user-assignable todo tasks. Present your full proposal.")
        XCTAssertFalse(timedOut, "Should complete without timeout")

        let final = manager.messages.last(where: { $0.role == .assistant && !$0.isDraft })
        let content = final?.content ?? ""
        print("[HARNESS] Final answer length: \(content.count)")
        print("[HARNESS] Final answer: \(content.prefix(600))")

        XCTAssertFalse(content.isEmpty, "Final answer must not be empty (streamed draft wiped)")
        XCTAssertFalse(
            content.contains("I could not complete this task"),
            "Final answer must not be the deterministic fallback that wiped the real proposal"
        )
        XCTAssertGreaterThan(content.count, 80, "Final answer should be a substantive proposal, got: \(content.prefix(200))")
    }

    // MARK: - Helpers

    @discardableResult
    private func send(_ text: String, timeout: TimeInterval = 180) async throws -> Bool {
        manager.currentInput = text
        manager.sendMessage()
        var lastProgressAt = Date()
        var lastMessageCount = manager.messages.count
        while true {
            if !manager.isSending { return false }
            let currentCount = manager.messages.count
            if currentCount != lastMessageCount {
                lastMessageCount = currentCount; lastProgressAt = Date()
            }
            if Date().timeIntervalSince(lastProgressAt) >= timeout { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if manager.isSending {
            manager.stopGeneration()
            _ = try await waitForFinish(manager, timeoutSeconds: 5)
            return true
        }
        return false
    }

    @discardableResult
    private func waitForFinish(_ manager: ConversationManager, timeoutSeconds: TimeInterval = 5) async throws -> Bool {
        var lastProgressAt = Date()
        while true {
            if !manager.isSending { return false }
            if Date().timeIntervalSince(lastProgressAt) >= timeoutSeconds { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return manager.isSending
    }

    private func extractToolCalls(from messages: [ChatMessage]) -> [String] {
        var tools: [String] = []
        for msg in messages where msg.isToolExecution {
            if let name = msg.toolName, !tools.contains(name) {
                tools.append(name)
            }
        }
        return tools
    }
}
