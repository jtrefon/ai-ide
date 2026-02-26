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
    
    override func setUp() async throws {
        try await super.setUp()
        // Set up test configuration for isolated testing
        await TestConfigurationProvider.shared.setConfiguration(.isolated)
        
        // Reset telemetry before each test
        ToolExecutionTelemetry.shared.reset()
    }
    
    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        try await super.tearDown()
    }
    
    // MARK: - Test: Empty Project Directory
    
    func testEmptyProjectDirectory() async throws {
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
        
        XCTAssertTrue(files.contains("README.md"), "Should create README.md")
        XCTAssertTrue(files.contains("src/main.py") || files.contains("main.py"), "Should create main.py")
        XCTAssertTrue(files.contains("requirements.txt"), "Should create requirements.txt")
    }
    
    // MARK: - Test: Large File Handling
    
    func testLargeFileHandling() async throws {
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
        XCTAssertTrue(files.contains("summary.txt"), "Should create summary.txt")
        
        let summaryContent = try String(contentsOf: projectRoot.appendingPathComponent("summary.txt"))
        XCTAssertTrue(summaryContent.contains(String(largeContent.prefix(100))), "Should contain first 100 characters")
        XCTAssertTrue(summaryContent.contains("\(largeContent.count)"), "Should contain character count")
    }
    
    // MARK: - Test: Malformed File Handling
    
    func testMalformedFileHandling() async throws {
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
        XCTAssertTrue(files.contains("report.txt"), "Should create report.txt")
        
        let reportContent = try String(contentsOf: projectRoot.appendingPathComponent("report.txt"))
        XCTAssertFalse(reportContent.isEmpty, "Report should not be empty")
        print("Report content: \(reportContent.prefix(200))...")
    }
    
    // MARK: - Test: Network Error Simulation
    
    func testNetworkErrorSimulation() async throws {
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
        XCTAssertFalse(localFiles.isEmpty, "Should create local files as fallback")
        
        print("Files created after network error: \(localFiles)")
    }
    
    // MARK: - Test: Concurrent File Operations
    
    func testConcurrentFileOperations() async throws {
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
        
        XCTAssertEqual(numberedFiles.count, 10, "Should create exactly 10 numbered files")
        XCTAssertTrue(files.contains("summary.txt"), "Should create summary.txt")
        
        let summaryContent = try String(contentsOf: projectRoot.appendingPathComponent("summary.txt"))
        for i in 1...10 {
            XCTAssertTrue(summaryContent.contains("file\(i).txt"), "Summary should mention file\(i).txt")
        }
    }
    
    // MARK: - Test: Memory Pressure Simulation
    
    func testMemoryPressureSimulation() async throws {
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
        
        XCTAssertEqual(dataFiles.count, 5, "Should create 5 data files")
        
        // Check telemetry for memory-related metrics
        let telemetry = ToolExecutionTelemetry.shared.summary
        print("\nTelemetry after memory pressure test:")
        print(telemetry.healthReport)
        
        XCTAssertGreaterThan(telemetry.successfulExecutions, 0, "Should have successful executions despite memory pressure")
    }
    
    // MARK: - Test: Tool Timeout Handling
    
    func testToolTimeoutHandling() async throws {
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
        XCTAssertTrue(files.contains("large_data.txt"), "Should create large data file")
        
        // Should have some result even if timeout occurred
        let resultFiles = files.filter { $0.contains("result") || $0.contains("output") || $0.contains("summary") }
        XCTAssertFalse(resultFiles.isEmpty, "Should have some result files")
        
        print("Files after timeout test: \(files)")
    }
    
    // MARK: - Helper Methods
    
    private struct ProductionRuntime {
        let container: DependencyContainer
        let manager: ConversationManager
    }
    
    private func makeProductionRuntime(projectRoot: URL) async throws -> ProductionRuntime {
        let container = DependencyContainer(launchContext: AppLaunchContext(mode: .unitTest, isTesting: true, isUITesting: false, testProfilePath: nil, disableHeavyInit: false))
        
        // Force offline mode to use local models only
        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        await selectionStore.setOfflineModeEnabled(true)
        
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
            .appendingPathComponent("edge_case_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
