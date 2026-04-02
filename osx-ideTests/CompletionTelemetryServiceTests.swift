import XCTest
@testable import osx_ide

final class CompletionTelemetryServiceTests: XCTestCase {
    func testTelemetryRequestsReducedWorkloadAfterSlowSuggestions() async {
        let telemetry = CompletionTelemetryService()

        await telemetry.recordShown(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "value",
                source: .local,
                confidenceScore: 0.9,
                latencyMs: 450
            )
        )
        await telemetry.recordShown(
            InlineSuggestionPresentation(
                requestId: UUID(),
                suggestionText: "otherValue",
                source: .local,
                confidenceScore: 0.8,
                latencyMs: 510
            )
        )

        let shouldReduceWorkload = await telemetry.shouldReduceWorkload()

        XCTAssertTrue(shouldReduceWorkload)
    }
}
