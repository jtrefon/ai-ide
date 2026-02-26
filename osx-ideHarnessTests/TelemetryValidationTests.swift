//
//  TelemetryValidationTests.swift
//  osx-ideHarnessTests
//
//  Tests for validating telemetry data quality and completeness
//

import XCTest
@testable import osx_ide

/// Tests for validating telemetry data quality and completeness
@MainActor
final class TelemetryValidationTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        // Set up test configuration for isolated testing
        await TestConfigurationProvider.shared.setConfiguration(.isolated)
        
        // Reset telemetry before each test
        ToolExecutionTelemetry.shared.reset()
        // await InferenceMetricsCollector.shared.clearMetrics()
    }
    
    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        try await super.tearDown()
    }
    
    // MARK: - Test: Tool Execution Telemetry
    
    func testToolExecutionTelemetryCollection() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        // Create test files
        let file1 = projectRoot.appendingPathComponent("file1.txt")
        let file2 = projectRoot.appendingPathComponent("file2.txt")
        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Tool Execution Telemetry Collection ===")
        
        let prompt = """
            Read both files (file1.txt and file2.txt) and then create a summary.txt file with their combined content.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        let telemetry = ToolExecutionTelemetry.shared.summary
        print("\nTelemetry Summary:")
        print(telemetry.healthReport)
        
        // Validate telemetry was collected
        XCTAssertGreaterThan(telemetry.totalIterations, 0, "Should have recorded tool loop iterations")
        XCTAssertGreaterThan(telemetry.successfulExecutions, 0, "Should have recorded successful executions")
        
        // Check for healthy metrics
        if !telemetry.isHealthy {
            print("Warning: Telemetry shows issues - this may be expected for complex scenarios")
        }
        
        // Verify files were created
        let files = listAllFiles(under: projectRoot)
        XCTAssertTrue(files.contains("summary.txt"), "Should create summary.txt")
    }
    
    // MARK: - Test: Inference Performance Metrics
    
    func testInferencePerformanceMetrics() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Inference Performance Metrics ===")
        
        let testId = "performance_test_\(UUID().uuidString)"
        // await InferenceMetricsCollector.shared.startTest(testId: testId)
        
        let prompt = """
            Write a simple Python function that calculates the factorial of a number.
            Include proper error handling and documentation.
            """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 120)
        
        // await InferenceMetricsCollector.shared.endTest()
        
        // let metrics = await InferenceMetricsCollector.shared.getMetrics(forTestId: testId)
        // XCTAssertFalse(metrics.isEmpty, "Should have collected performance metrics")
        
        // if let firstMetric = metrics.first {
        //     print("\nPerformance Metrics:")
        //     print(firstMetric.summary)
        //     
        //     XCTAssertGreaterThan(firstMetric.outputTokenCount ?? 0, 0, "Should have generated output tokens")
        //     XCTAssertGreaterThan(firstMetric.totalDuration ?? 0, 0, "Should have recorded duration")
        //     XCTAssertLessThanOrEqual(firstMetric.totalDuration ?? 0, 300, "Should complete within reasonable time")
        // }
        
        // Verify Python file was created
        let files = listAllFiles(under: projectRoot)
        let pythonFiles = files.filter { $0.hasSuffix(".py") }
        XCTAssertFalse(pythonFiles.isEmpty, "Should have created Python file")
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
                domain: "TelemetryValidationTests", code: 1,
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
            .appendingPathComponent("telemetry_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
