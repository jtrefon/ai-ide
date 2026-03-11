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
        print("\n=== Test: Tool Execution Telemetry Collection ===")

        ToolExecutionTelemetry.shared.recordIteration()
        ToolExecutionTelemetry.shared.recordSuccessfulExecution()
        ToolExecutionTelemetry.shared.recordDeduplicatedToolCalls(count: 1)
        ToolExecutionTelemetry.shared.recordRepeatedAssistantUpdate()
        
        let telemetry = ToolExecutionTelemetry.shared.summary
        print("\nTelemetry Summary:")
        print(telemetry.healthReport)

        XCTAssertEqual(telemetry.totalIterations, 1)
        XCTAssertEqual(telemetry.successfulExecutions, 1)
        XCTAssertEqual(telemetry.deduplicatedToolCalls, 1)
        XCTAssertEqual(telemetry.repeatedAssistantUpdates, 1)
        XCTAssertFalse(telemetry.isHealthy)
    }
    
    // MARK: - Test: Inference Performance Metrics
    
    func testInferencePerformanceMetrics() async throws {
        print("\n=== Test: Inference Performance Metrics ===")
        let eventBus = EventBus()
        let aggregator = RAGTelemetryAggregator(eventBus: eventBus)

        eventBus.publish(
            RAGRetrievalCompletedEvent(
                symbolCount: 1,
                overviewCount: 1,
                memoryCount: 0,
                segmentCount: 1,
                evidenceCount: 2,
                retrievalIntent: "tests",
                retrievalConfidence: 0.9,
                contextCharCount: 800
            )
        )
        eventBus.publish(DuplicateRiskDetectedEvent(summary: "duplicate implementation", severity: "critical"))
        eventBus.publish(
            PreWritePreventionCheckCompletedEvent(
                toolName: "write_file",
                outcome: "block",
                findingCount: 1
            )
        )

        await Task.yield()

        let snapshot = aggregator.generateSnapshot()
        XCTAssertEqual(snapshot.totalRetrievals, 1)
        XCTAssertEqual(snapshot.totalViolations, 1)
        XCTAssertGreaterThan(snapshot.contextTokenEfficiency, 0)
        XCTAssertGreaterThanOrEqual(snapshot.policyViolationRate, 0)
    }
}
