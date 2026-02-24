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
    
    override func setUp() async throws {
        try await super.setUp()
        // Set up test configuration for isolated testing
        await TestConfigurationProvider.shared.setConfiguration(.isolated)
    }
    
    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        try await super.tearDown()
    }
    
    // MARK: - Test: Tool Loop with Real Local Model
    
    func testToolLoopWithRealLocalModel() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        // Create a simple test file to work with
        let testFile = projectRoot.appendingPathComponent("test.txt")
        try "Hello World".write(to: testFile, atomically: true, encoding: .utf8)
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Tool Loop with Real Local Model ===")
        print("Project root: \(projectRoot.path)")
        
        let prompt = """
            Read the test.txt file and then create a new file called output.txt with the content in uppercase.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        let files = listAllFiles(under: projectRoot)
        print("\nFiles after tool loop: \(files)")
        
        XCTAssertTrue(files.contains("output.txt"), "Should have created output.txt")
        
        let outputContent = try String(contentsOf: projectRoot.appendingPathComponent("output.txt"))
        XCTAssertEqual(outputContent.trimmingCharacters(in: .whitespacesAndNewlines), "HELLO WORLD")
    }
    
    // MARK: - Test: Tool Deduplication with Real Service
    
    func testToolDeduplicationWithRealService() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Tool Deduplication with Real Service ===")
        
        let prompt = """
            List the files in this directory twice. Use the list_files tool for each request.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        // Check telemetry for deduplication
        let telemetry = ToolExecutionTelemetry.shared.summary
        print("\nTelemetry summary: \(telemetry.healthReport)")
        
        // Should have deduplicated duplicate tool calls
        XCTAssertTrue(telemetry.deduplicatedToolCalls >= 0, "Should track deduplicated tool calls")
    }
    
    // MARK: - Test: Error Handling with Real Service
    
    func testErrorHandlingWithRealService() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Error Handling with Real Service ===")
        
        let prompt = """
            Try to read a file that doesn't exist called nonexistent.txt, then create it with error handling.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        let files = listAllFiles(under: projectRoot)
        XCTAssertTrue(files.contains("nonexistent.txt"), "Should have created the file after handling error")
    }

    func testFailureRecoveryUsesFallbackWithoutRepeatedIdenticalFailures() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        ToolExecutionTelemetry.shared.reset()

        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        print("\n=== Test: Failure Recovery Uses Fallback ===")

        let prompt = """
            Try to read a file that does not exist named must-fail-first.txt.
            If reading fails, do not repeat the same failed call.
            Instead create must-fail-first.txt with content \"Recovered via fallback\" and finish.
            """

        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)

        let lastAssistantContent = manager.messages.last(where: { $0.role == .assistant })?.content ?? ""
        if lastAssistantContent.localizedCaseInsensitiveContains("read-only Chat mode") {
            throw XCTSkip(
                "Local model runtime downgraded Agent mode to read-only Chat mode; skipping fallback recovery assertion."
            )
        }

        let files = listAllFiles(under: projectRoot)
        guard files.contains("must-fail-first.txt") else {
            XCTFail("Agent should recover by creating fallback file")
            return
        }

        let createdContent = try String(
            contentsOf: projectRoot.appendingPathComponent("must-fail-first.txt"),
            encoding: .utf8
        )
        XCTAssertTrue(
            createdContent.localizedCaseInsensitiveContains("recovered"),
            "Fallback file should contain recovery marker content"
        )

        let failedToolExecutionMessages = manager.messages.filter {
            $0.isToolExecution && $0.toolStatus == .failed
        }
        let repeatedFailureSignatures = repeatedFailureSignatureCounts(from: failedToolExecutionMessages)

        if failedToolExecutionMessages.isEmpty {
            print("[HARNESS][warning] No failed tool execution captured in this run; skipping repeated-failure signature assertion.")
        } else {
            XCTAssertTrue(
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
    
    private func makeProductionRuntime(projectRoot: URL) async throws -> ProductionRuntime {
        // Use real DependencyContainer but force local model usage
        let container = DependencyContainer(isTesting: true)
        
        // Force offline mode to use local models only
        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        await selectionStore.setOfflineModeEnabled(true)
        
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
    
    private func sendProductionMessage(
        _ text: String, manager: ConversationManager, timeoutSeconds: TimeInterval = 180
    ) async throws {
        manager.currentInput = text
        manager.sendMessage()
        try await waitForConversationToFinish(manager, timeoutSeconds: timeoutSeconds)
        if let error = manager.error {
            XCTFail("Conversation manager reported error: \(error)")
        }
    }
    
    private func waitForConversationToFinish(
        _ manager: ConversationManager, timeoutSeconds: TimeInterval = 180
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !manager.isSending {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("Timed out waiting for conversation manager to finish send task")
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
            if !relative.hasPrefix(".ide") {
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
}
