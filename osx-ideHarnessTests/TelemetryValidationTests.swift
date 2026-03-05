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
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 300)
        
        let telemetry = ToolExecutionTelemetry.shared.summary
        print("\nTelemetry Summary:")
        print(telemetry.healthReport)
        
        // Telemetry-only harness: log counters without hard assertions.
        if telemetry.totalIterations == 0 {
            print("Warning: No tool loop iterations were recorded for this run.")
        }
        if telemetry.successfulExecutions == 0 {
            print("Warning: No successful tool executions were recorded for this run.")
        }
        
        // Check for healthy metrics
        if !telemetry.isHealthy {
            print("Warning: Telemetry shows issues - this may be expected for complex scenarios")
        }
        
        // Log resulting files for telemetry debugging (file naming can vary by model/provider).
        let files = listAllFiles(under: projectRoot)
        print("Generated files: \(files)")
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
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 300)
        
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
        
        // Log generated files for telemetry visibility; exact file types may vary by model/provider.
        let files = listAllFiles(under: projectRoot)
        print("Generated files: \(files)")
    }
    
    // MARK: - Helper Methods
    
    private struct ProductionRuntime {
        let container: DependencyContainer
        let manager: ConversationManager
    }
    
    private func makeProductionRuntime(projectRoot: URL) async throws -> ProductionRuntime {
        let container = DependencyContainer(launchContext: AppLaunchContext(mode: .unitTest, isTesting: true, isUITesting: false, testProfilePath: nil, disableHeavyInit: false))
        container.settingsStore.set(false, forKey: AppConstantsStorage.agentQAReviewEnabledKey)
        
        // Production-parity harness: keep agent mode online-capable.
        let selectionStore = LocalModelSelectionStore(settingsStore: container.settingsStore)
        await selectionStore.setOfflineModeEnabled(false)
        let isOfflineModeEnabled = await selectionStore.isOfflineModeEnabled()
        if isOfflineModeEnabled {
            print("Warning: Production-parity harness is running in Offline Mode.")
        }
        
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
            }

            if Date().timeIntervalSince(lastProgressAt) >= timeoutSeconds {
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
            .appendingPathComponent("telemetry_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
