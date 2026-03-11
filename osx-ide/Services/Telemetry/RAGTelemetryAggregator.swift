import Foundation
import Combine

/// Aggregates RAG and prevention telemetry events into KPI metrics
public class RAGTelemetryAggregator {
    private let eventBus: EventBusProtocol
    private var subscriptions: [AnyCancellable] = []
    
    // KPI Accumulators
    private var duplicateIncidentCount: Int = 0
    private var deadCodeIncidentCount: Int = 0
    private var totalRetrievals: Int = 0
    private var successfulIntegrations: Int = 0
    private var totalPatches: Int = 0
    private var policyViolations: Int = 0
    private var retryCount: Int = 0
    
    private var retrievalLatencies: [TimeInterval] = []
    private var contextTokenCounts: [(useful: Int, total: Int)] = []
    private var toolCallsByStage: [String: Int] = [:]
    
    private let startTime: Date
    
    public init(eventBus: EventBusProtocol) {
        self.eventBus = eventBus
        self.startTime = Date()
        subscribeToEvents()
    }
    
    private func subscribeToEvents() {
        // Duplicate and dead code incidents
        subscriptions.append(
            eventBus.subscribe(to: DuplicateRiskDetectedEvent.self) { [weak self] _ in
                self?.duplicateIncidentCount += 1
            }
        )
        
        subscriptions.append(
            eventBus.subscribe(to: DeadCodeRiskDetectedEvent.self) { [weak self] _ in
                self?.deadCodeIncidentCount += 1
            }
        )
        
        // Retrieval metrics
        subscriptions.append(
            eventBus.subscribe(to: RAGRetrievalCompletedEvent.self) { [weak self] event in
                self?.totalRetrievals += 1
                self?.contextTokenCounts.append((useful: event.evidenceCount, total: event.contextCharCount / 4))
            }
        )
        
        // Prevention policy violations
        subscriptions.append(
            eventBus.subscribe(to: PreWritePreventionCheckCompletedEvent.self) { [weak self] event in
                if event.outcome == "block" {
                    self?.policyViolations += 1
                }
            }
        )
    }
    
    // MARK: - KPI Calculations
    
    /// KPI 1: Duplicate implementation incident rate (per 100 patches)
    public func duplicateIncidentRate() -> Double {
        guard totalPatches > 0 else { return 0.0 }
        return Double(duplicateIncidentCount) / Double(totalPatches) * 100.0
    }
    
    /// KPI 2: Dead code introduction rate (per 100 patches)
    public func deadCodeIntroductionRate() -> Double {
        guard totalPatches > 0 else { return 0.0 }
        return Double(deadCodeIncidentCount) / Double(totalPatches) * 100.0
    }
    
    /// KPI 3: Retrieval precision@K for accepted edits
    public func retrievalPrecision() -> Double {
        guard totalRetrievals > 0 else { return 0.0 }
        // Simplified: assume precision based on successful integrations
        return Double(successfulIntegrations) / Double(totalRetrievals)
    }
    
    /// KPI 4: First-pass successful integration rate
    public func firstPassSuccessRate() -> Double {
        guard totalPatches > 0 else { return 0.0 }
        return Double(successfulIntegrations) / Double(totalPatches)
    }
    
    /// KPI 5: Mean time to safe patch (seconds)
    public func meanTimeToSafePatch() -> TimeInterval {
        let elapsed = Date().timeIntervalSince(startTime)
        guard totalPatches > 0 else { return elapsed }
        return elapsed / Double(totalPatches)
    }
    
    /// KPI 6: Average end-to-end turn latency (seconds)
    public func averageTurnLatency() -> TimeInterval {
        guard !retrievalLatencies.isEmpty else { return 0.0 }
        return retrievalLatencies.reduce(0, +) / Double(retrievalLatencies.count)
    }
    
    /// KPI 7: Tool-call success rate per stage
    public func toolCallSuccessRate(stage: String) -> Double {
        let calls = toolCallsByStage[stage] ?? 0
        guard calls > 0 else { return 0.0 }
        // Simplified: assume success rate based on non-blocked calls
        return 1.0 - (Double(policyViolations) / Double(calls))
    }
    
    /// KPI 8: Context token efficiency (useful/total)
    public func contextTokenEfficiency() -> Double {
        guard !contextTokenCounts.isEmpty else { return 0.0 }
        let totalUseful = contextTokenCounts.reduce(0) { $0 + $1.useful }
        let totalTokens = contextTokenCounts.reduce(0) { $0 + $1.total }
        guard totalTokens > 0 else { return 0.0 }
        return Double(totalUseful) / Double(totalTokens)
    }
    
    /// KPI 9: Policy violation rate
    public func policyViolationRate() -> Double {
        guard totalPatches > 0 else { return 0.0 }
        return Double(policyViolations) / Double(totalPatches)
    }
    
    /// KPI 10: Retry rate per task category
    public func retryRate() -> Double {
        guard totalPatches > 0 else { return 0.0 }
        return Double(retryCount) / Double(totalPatches)
    }
    
    // MARK: - Snapshot Generation
    
    /// Generate a complete KPI snapshot for reporting
    public func generateSnapshot() -> RAGTelemetrySnapshot {
        return RAGTelemetrySnapshot(
            timestamp: Date(),
            duplicateIncidentRate: duplicateIncidentRate(),
            deadCodeIntroductionRate: deadCodeIntroductionRate(),
            retrievalPrecision: retrievalPrecision(),
            firstPassSuccessRate: firstPassSuccessRate(),
            meanTimeToSafePatch: meanTimeToSafePatch(),
            averageTurnLatency: averageTurnLatency(),
            contextTokenEfficiency: contextTokenEfficiency(),
            policyViolationRate: policyViolationRate(),
            retryRate: retryRate(),
            totalPatches: totalPatches,
            totalRetrievals: totalRetrievals,
            totalViolations: policyViolations
        )
    }
    
    /// Export snapshot as markdown for QUALITY_TRACKER.md
    public func exportMarkdown() -> String {
        let snapshot = generateSnapshot()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        return """
        ## RAG & Prevention Metrics Snapshot
        
        **Generated:** \(formatter.string(from: snapshot.timestamp))
        
        ### Quality Metrics
        - **Duplicate Incident Rate:** \(String(format: "%.2f", snapshot.duplicateIncidentRate))% (per 100 patches)
        - **Dead Code Introduction Rate:** \(String(format: "%.2f", snapshot.deadCodeIntroductionRate))% (per 100 patches)
        - **Policy Violation Rate:** \(String(format: "%.2f", snapshot.policyViolationRate * 100))%
        
        ### Retrieval Performance
        - **Retrieval Precision@K:** \(String(format: "%.2f", snapshot.retrievalPrecision * 100))%
        - **Context Token Efficiency:** \(String(format: "%.2f", snapshot.contextTokenEfficiency * 100))%
        - **Total Retrievals:** \(snapshot.totalRetrievals)
        
        ### Integration Success
        - **First-Pass Success Rate:** \(String(format: "%.2f", snapshot.firstPassSuccessRate * 100))%
        - **Mean Time to Safe Patch:** \(String(format: "%.1f", snapshot.meanTimeToSafePatch))s
        - **Average Turn Latency:** \(String(format: "%.2f", snapshot.averageTurnLatency))s
        - **Retry Rate:** \(String(format: "%.2f", snapshot.retryRate * 100))%
        
        ### Summary
        - **Total Patches:** \(snapshot.totalPatches)
        - **Total Violations:** \(snapshot.totalViolations)
        
        """
    }
}

// MARK: - Models

public struct RAGTelemetrySnapshot: Codable, Sendable {
    public let timestamp: Date
    public let duplicateIncidentRate: Double
    public let deadCodeIntroductionRate: Double
    public let retrievalPrecision: Double
    public let firstPassSuccessRate: Double
    public let meanTimeToSafePatch: TimeInterval
    public let averageTurnLatency: TimeInterval
    public let contextTokenEfficiency: Double
    public let policyViolationRate: Double
    public let retryRate: Double
    public let totalPatches: Int
    public let totalRetrievals: Int
    public let totalViolations: Int
}
