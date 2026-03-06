import XCTest
import Combine
@testable import osx_ide

@MainActor
final class RAGTelemetryAggregatorTests: XCTestCase {
    func testAggregatesRetrievalEventsIntoSnapshot() async {
        let eventBus = EventBus()
        let aggregator = RAGTelemetryAggregator(eventBus: eventBus)

        eventBus.publish(
            RAGRetrievalCompletedEvent(
                symbolCount: 2,
                overviewCount: 1,
                memoryCount: 1,
                segmentCount: 3,
                evidenceCount: 6,
                retrievalIntent: "bug_fix",
                retrievalConfidence: 0.82,
                contextCharCount: 1600
            )
        )

        await Task.yield()

        let snapshot = aggregator.generateSnapshot()

        XCTAssertEqual(snapshot.totalRetrievals, 1)
        XCTAssertEqual(snapshot.totalViolations, 0)
        XCTAssertGreaterThan(snapshot.contextTokenEfficiency, 0.0)
        XCTAssertEqual(snapshot.policyViolationRate, 0.0)
    }

    func testAggregatesPreventionRiskAndPolicyViolationEvents() async {
        let eventBus = EventBus()
        let aggregator = RAGTelemetryAggregator(eventBus: eventBus)

        eventBus.publish(DuplicateRiskDetectedEvent(summary: "duplicate implementation", severity: "critical"))
        eventBus.publish(DeadCodeRiskDetectedEvent(summary: "orphan symbol", severity: "warning"))
        eventBus.publish(
            PreWritePreventionCheckCompletedEvent(
                toolName: "write_file",
                outcome: "block",
                findingCount: 2
            )
        )

        await Task.yield()

        let snapshot = aggregator.generateSnapshot()
        let markdown = aggregator.exportMarkdown()

        XCTAssertEqual(snapshot.totalViolations, 1)
        XCTAssertGreaterThanOrEqual(snapshot.policyViolationRate, 0.0)
        XCTAssertTrue(markdown.contains("Policy Violation Rate"))
        XCTAssertTrue(markdown.contains("**Total Violations:** 1"))
    }
}
