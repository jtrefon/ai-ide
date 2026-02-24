import Foundation

/// Telemetry tracking for tool execution quality metrics.
/// Tracks cases where model responses don't contain recognized tool calls
/// or contain repeated content/batches.
@MainActor
final class ToolExecutionTelemetry {
    static let shared = ToolExecutionTelemetry()
    
    private init() {}
    
    // MARK: - Tool Miss Tracking
    
    /// Number of responses where model should have returned tool calls but didn't.
    private(set) var responsesWithoutToolCalls: Int = 0
    
    /// Number of responses where model wrote textual tool call patterns (e.g., "tool calls:")
    /// but no actual tool calls were parsed.
    private(set) var textualToolCallPatterns: Int = 0
    
    // MARK: - Repeat Tracking
    
    /// Number of tool calls that were deduplicated (repeated within same batch).
    private(set) var deduplicatedToolCalls: Int = 0
    
    /// Number of repeated tool batches (same batch called multiple times).
    private(set) var repeatedBatches: Int = 0
    
    /// Number of repeated content responses without tool calls.
    private(set) var repeatedContent: Int = 0

    /// Number of repeated assistant update messages observed during tool loops.
    private(set) var repeatedAssistantUpdates: Int = 0

    /// Number of repeated tool-call signatures observed across iterations.
    private(set) var repeatedToolCallSignatures: Int = 0
    
    // MARK: - Session Tracking
    
    /// Total number of tool loop iterations.
    private(set) var totalIterations: Int = 0
    
    /// Total number of successful tool executions.
    private(set) var successfulExecutions: Int = 0
    
    // MARK: - Recording Methods
    
    /// Record a response that should have contained tool calls but didn't.
    func recordResponseWithoutToolCalls(hasTextualPattern: Bool) {
        responsesWithoutToolCalls += 1
        if hasTextualPattern {
            textualToolCallPatterns += 1
        }
        logTelemetry()
    }
    
    /// Record deduplicated tool calls.
    func recordDeduplicatedToolCalls(count: Int) {
        deduplicatedToolCalls += count
        logTelemetry()
    }
    
    /// Record a repeated tool batch.
    func recordRepeatedBatch() {
        repeatedBatches += 1
        logTelemetry()
    }
    
    /// Record repeated content without tool calls.
    func recordRepeatedContent() {
        repeatedContent += 1
        logTelemetry()
    }

    /// Record repeated assistant update observation.
    func recordRepeatedAssistantUpdate() {
        repeatedAssistantUpdates += 1
        logTelemetry()
    }

    /// Record repeated tool-call signature observation.
    func recordRepeatedToolCallSignatures(count: Int) {
        guard count > 0 else { return }
        repeatedToolCallSignatures += count
        logTelemetry()
    }
    
    /// Record a tool loop iteration.
    func recordIteration() {
        totalIterations += 1
    }
    
    /// Record a successful tool execution.
    func recordSuccessfulExecution() {
        successfulExecutions += 1
    }
    
    // MARK: - Summary
    
    /// Returns a summary of all telemetry data.
    var summary: ToolExecutionTelemetrySummary {
        ToolExecutionTelemetrySummary(
            responsesWithoutToolCalls: responsesWithoutToolCalls,
            textualToolCallPatterns: textualToolCallPatterns,
            deduplicatedToolCalls: deduplicatedToolCalls,
            repeatedBatches: repeatedBatches,
            repeatedContent: repeatedContent,
            repeatedAssistantUpdates: repeatedAssistantUpdates,
            repeatedToolCallSignatures: repeatedToolCallSignatures,
            totalIterations: totalIterations,
            successfulExecutions: successfulExecutions
        )
    }
    
    /// Reset all counters (useful for testing).
    func reset() {
        responsesWithoutToolCalls = 0
        textualToolCallPatterns = 0
        deduplicatedToolCalls = 0
        repeatedBatches = 0
        repeatedContent = 0
        repeatedAssistantUpdates = 0
        repeatedToolCallSignatures = 0
        totalIterations = 0
        successfulExecutions = 0
    }
    
    // MARK: - Private
    
    private func logTelemetry() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await AIToolTraceLogger.shared.log(
                type: "telemetry.tool_execution",
                data: [
                    "responsesWithoutToolCalls": await self.responsesWithoutToolCalls,
                    "textualToolCallPatterns": await self.textualToolCallPatterns,
                    "deduplicatedToolCalls": await self.deduplicatedToolCalls,
                    "repeatedBatches": await self.repeatedBatches,
                    "repeatedContent": await self.repeatedContent,
                    "repeatedAssistantUpdates": await self.repeatedAssistantUpdates,
                    "repeatedToolCallSignatures": await self.repeatedToolCallSignatures,
                    "totalIterations": await self.totalIterations,
                    "successfulExecutions": await self.successfulExecutions
                ]
            )
        }
    }
}

/// Immutable summary of telemetry data.
struct ToolExecutionTelemetrySummary: Codable {
    let responsesWithoutToolCalls: Int
    let textualToolCallPatterns: Int
    let deduplicatedToolCalls: Int
    let repeatedBatches: Int
    let repeatedContent: Int
    let repeatedAssistantUpdates: Int
    let repeatedToolCallSignatures: Int
    let totalIterations: Int
    let successfulExecutions: Int
    
    /// Returns true if all quality metrics are at target (0).
    var isHealthy: Bool {
        responsesWithoutToolCalls == 0 &&
        textualToolCallPatterns == 0 &&
        deduplicatedToolCalls == 0 &&
        repeatedBatches == 0 &&
        repeatedContent == 0 &&
        repeatedAssistantUpdates == 0 &&
        repeatedToolCallSignatures == 0
    }
    
    /// Returns a human-readable health report.
    var healthReport: String {
        var issues: [String] = []
        if responsesWithoutToolCalls > 0 {
            issues.append("Responses without tool calls: \(responsesWithoutToolCalls)")
        }
        if textualToolCallPatterns > 0 {
            issues.append("Textual tool call patterns (not parsed): \(textualToolCallPatterns)")
        }
        if deduplicatedToolCalls > 0 {
            issues.append("Deduplicated tool calls: \(deduplicatedToolCalls)")
        }
        if repeatedBatches > 0 {
            issues.append("Repeated batches: \(repeatedBatches)")
        }
        if repeatedContent > 0 {
            issues.append("Repeated content: \(repeatedContent)")
        }
        if repeatedAssistantUpdates > 0 {
            issues.append("Repeated assistant updates observed: \(repeatedAssistantUpdates)")
        }
        if repeatedToolCallSignatures > 0 {
            issues.append("Repeated tool-call signatures observed: \(repeatedToolCallSignatures)")
        }
        
        if issues.isEmpty {
            return "Tool execution telemetry: All metrics at target (0). Iterations: \(totalIterations), Successful: \(successfulExecutions)"
        } else {
            return "Tool execution telemetry issues:\n" + issues.joined(separator: "\n")
        }
    }
}
