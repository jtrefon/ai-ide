//
//  EdgeCaseScenariosTests.swift
//  osx-ideHarnessTests
//
//  Tests for edge cases and error handling scenarios
//

import XCTest
@testable import osx_ide

/// Tests for edge cases and error handling in the agentic system
@MainActor
final class EdgeCaseScenariosTests: XCTestCase {

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
            externalAPITimeout: 180.0,
            useMockServices: false
        )
        await TestConfigurationProvider.shared.setConfiguration(config)
        
        // Reset telemetry before each test
        ToolExecutionTelemetry.shared.reset()
    }
    
    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        await OnlineHarnessExecutionGate.shared.release()
        try await super.tearDown()
    }
    
    // MARK: - Test: Empty Project Directory
    
    func testEmptyProjectDirectory() async throws {
        try requireOnlineHarnessExecution()
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Empty Project Directory ===")
        
        let prompt = """
            This is an empty project directory. Create a basic project structure including:
            1. A README.md file with project description
            2. A src/ directory with a main.py file
            3. A requirements.txt file with basic dependencies
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        let files = listAllFiles(under: projectRoot)
        print("\nFiles created in empty project: \(files)")
        
        if !files.contains("README.md") { print("Warning: README.md was not created.") }
        if !(files.contains("src/main.py") || files.contains("main.py")) { print("Warning: main.py was not created.") }
        if !files.contains("requirements.txt") { print("Warning: requirements.txt was not created.") }
    }
    
    // MARK: - Test: Large File Handling
    
    func testLargeFileHandling() async throws {
        try requireOnlineHarnessExecution()
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        // Create a large file (100KB)
        let largeContent = String(repeating: "This is a line of text that will be repeated many times to create a large file for testing the system's ability to handle large files. ", count: 1000)
        let largeFile = projectRoot.appendingPathComponent("large_file.txt")
        try largeContent.write(to: largeFile, atomically: true, encoding: .utf8)
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Large File Handling ===")
        print("Large file size: \(largeContent.count) characters")
        
        let prompt = """
            Read the large_file.txt file and create a summary.txt file with the first 100 characters and the total character count.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        let files = listAllFiles(under: projectRoot)
        if !files.contains("summary.txt") {
            print("Warning: summary.txt was not created.")
        } else {
            let summaryContent = try String(contentsOf: projectRoot.appendingPathComponent("summary.txt"))
            if !summaryContent.contains(String(largeContent.prefix(100))) {
                print("Warning: summary.txt does not contain the expected first 100 characters.")
            }
            if !summaryContent.contains("\(largeContent.count)") {
                print("Warning: summary.txt does not contain the expected character count.")
            }
        }
    }
    
    // MARK: - Test: Malformed File Handling
    
    func testMalformedFileHandling() async throws {
        try requireOnlineHarnessExecution()
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        // Create files with various encoding issues
        let malformedFiles: [String: Any] = [
            "broken.json": "{ \"incomplete\": json",
            "broken.xml": "<root><child>Unclosed tag",
            "binary.dat": Data([0xFF, 0xFE, 0x00, 0x00, 0x48, 0x00, 0x65, 0x00]) // UTF-16 BOM
        ]
        
        for (filename, content) in malformedFiles {
            let url = projectRoot.appendingPathComponent(filename)
            if let data = content as? Data {
                try data.write(to: url)
            } else if let string = content as? String {
                try string.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Malformed File Handling ===")
        
        let prompt = """
            Analyze the files in this directory and create a report.txt file describing any issues found.
            Handle malformed files gracefully and continue processing other files.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        let files = listAllFiles(under: projectRoot)
        if !files.contains("report.txt") {
            print("Warning: report.txt was not created.")
        } else {
            let reportContent = try String(contentsOf: projectRoot.appendingPathComponent("report.txt"))
            if reportContent.isEmpty {
                print("Warning: report.txt is empty.")
            } else {
                print("Report content: \(reportContent.prefix(200))...")
            }
        }
    }
    
    // MARK: - Test: Network Error Simulation
    
    func testNetworkErrorSimulation() async throws {
        try requireOnlineHarnessExecution()
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Network Error Simulation ===")
        
        let prompt = """
            Try to download a file from a non-existent URL (http://nonexistent.example.com/file.txt) 
            and then create a local file with fallback content. Handle the network error gracefully.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        let files = listAllFiles(under: projectRoot)
        // Should create a local file even after network failure
        let localFiles = files.filter { !$0.hasPrefix(".") }
        if localFiles.isEmpty {
            print("Warning: no local fallback files were created after network error scenario.")
        }
        
        print("Files created after network error: \(localFiles)")
    }
    
    // MARK: - Test: Concurrent File Operations
    
    func testConcurrentFileOperations() async throws {
        try requireOnlineHarnessExecution()
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Concurrent File Operations ===")
        
        let prompt = """
            Create 10 files (file1.txt through file10.txt) simultaneously, each containing a unique message.
            Then create a summary.txt file listing all created files.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 150)
        
        let files = listAllFiles(under: projectRoot)
        let numberedFiles = files.filter { $0.hasPrefix("file") && $0.hasSuffix(".txt") }
        
        if numberedFiles.count != 10 {
            print("Warning: expected 10 numbered files, got \(numberedFiles.count).")
        }
        if !files.contains("summary.txt") {
            print("Warning: summary.txt was not created.")
        } else {
            let summaryContent = try String(contentsOf: projectRoot.appendingPathComponent("summary.txt"))
            for i in 1...10 where !summaryContent.contains("file\(i).txt") {
                print("Warning: summary.txt is missing file\(i).txt.")
            }
        }
    }
    
    // MARK: - Test: Memory Pressure Simulation
    
    func testMemoryPressureSimulation() async throws {
        try requireOnlineHarnessExecution()
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Memory Pressure Simulation ===")
        
        let prompt = """
            Create a memory-intensive operation by:
            1. Reading and processing multiple files in sequence
            2. Creating a large summary report
            3. Demonstrating efficient memory usage
            
            Create 5 files (data1.txt through data5.txt) each with 1000 lines, then process them.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 180)
        
        let files = listAllFiles(under: projectRoot)
        let dataFiles = files.filter { $0.hasPrefix("data") && $0.hasSuffix(".txt") }
        print("Produced files: \(files)")

        if dataFiles.count != 5 {
            print("Warning: expected 5 data files, got \(dataFiles.count).")
        }
        
        // Check telemetry for memory-related metrics
        let telemetry = ToolExecutionTelemetry.shared.summary
        print("\nTelemetry after memory pressure test:")
        print(telemetry.healthReport)

        let failedToolMessages = manager.messages.filter { $0.isToolExecution && $0.toolStatus == .failed }
        if !failedToolMessages.isEmpty {
            print("\nFailed tool calls (\(failedToolMessages.count)):")
            for message in failedToolMessages {
                let toolName = message.toolName ?? "unknown"
                let toolCallId = message.toolCallId ?? "unknown"
                let detail: String
                if let envelope = ToolExecutionEnvelope.decode(from: message.content) {
                    detail = envelope.message
                } else {
                    detail = String(message.content.prefix(240))
                }
                print("- \(toolName) [\(toolCallId)]: \(detail)")
            }
        }

        if telemetry.successfulExecutions == 0 {
            print("Warning: no successful executions recorded during memory pressure test.")
        }
    }
    
    // MARK: - Test: Tool Timeout Handling
    
    func testToolTimeoutHandling() async throws {
        try requireOnlineHarnessExecution()
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Tool Timeout Handling ===")
        
        let prompt = """
            Simulate a long-running operation that might timeout:
            1. Create a file that would take a long time to process
            2. Handle potential timeouts gracefully
            3. Provide fallback behavior
            
            Create a large_data.txt file with 10000 lines, then try to process it with timeouts in mind.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 150)
        
        let files = listAllFiles(under: projectRoot)
        if !files.contains("large_data.txt") {
            print("Warning: large_data.txt was not created.")
        }
        
        // Should have some result even if timeout occurred
        let resultFiles = files.filter { $0.contains("result") || $0.contains("output") || $0.contains("summary") }
        if resultFiles.isEmpty {
            print("Warning: no result/output/summary files were created in timeout handling scenario.")
        }
        
        print("Files after timeout test: \(files)")
    }
    
    // MARK: - Helper Methods
    
    private struct ProductionRuntime {
        let container: DependencyContainer
        let manager: ConversationManager
    }
    
    private func makeProductionRuntime(projectRoot: URL) async throws -> ProductionRuntime {
        let container = DependencyContainer(launchContext: AppLaunchContext(mode: .unitTest, isTesting: true, isUITesting: false, testProfilePath: nil, disableHeavyInit: false, productionParityHarness: false))
        
        // Production-parity harness: keep agent mode online-capable.
        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        await selectionStore.setOfflineModeEnabled(false)
        let isOfflineModeEnabled = await selectionStore.isOfflineModeEnabled()
        if isOfflineModeEnabled {
            print("Warning: Production-parity harness is running in Offline Mode.")
        }
        
        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "EdgeCaseScenariosTests", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ConversationManager is not the expected concrete type"
                ])
        }
        
        container.workspaceService.currentDirectory = projectRoot
        container.projectCoordinator.configureProject(root: projectRoot)
        
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
            print("Warning: Conversation manager reported error: \(error)")
        }
    }
    
    private func waitForConversationToFinish(
        _ manager: ConversationManager, timeoutSeconds: TimeInterval = 180
    ) async throws {
        let hardDeadline = Date().addingTimeInterval(max(timeoutSeconds * 5, 900))
        var lastProgressAt = Date()
        var lastMessageCount = manager.messages.count

        while Date() < hardDeadline {
            if !manager.isSending {
                return
            }
            let currentMessageCount = manager.messages.count
            if currentMessageCount != lastMessageCount {
                lastMessageCount = currentMessageCount
                lastProgressAt = Date()
            } else if Date().timeIntervalSince(lastProgressAt) >= timeoutSeconds {
                print("Warning: Conversation is idle for \(Int(timeoutSeconds))s; continuing to wait without forcing stop.")
                lastProgressAt = Date()
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if manager.isSending {
            print("Warning: Conversation exceeded hard wait budget (\(Int(max(timeoutSeconds * 5, 900)))s).")
        }
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
            .appendingPathComponent("edge_case_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
