import SwiftUI
import Combine

/// Composite status gauge showing RAG system health metrics
/// - Readiness: Index freshness + enrichment coverage + retrieval confidence
/// - Debt Pressure: Duplicate risk + dead code risk + quality trend
/// - Guard Status: Prevention gate state (clear/warn/block)
struct RAGStatusGauge: View {
    @ObservedObject var viewModel: RAGStatusGaugeViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Readiness metric
            MetricIndicator(
                label: "Ready",
                value: viewModel.readinessScore,
                color: readinessColor(viewModel.readinessScore),
                icon: "checkmark.circle.fill"
            )
            
            Divider()
                .frame(height: 20)
            
            // Debt pressure metric
            MetricIndicator(
                label: "Debt",
                value: viewModel.debtPressure,
                color: debtColor(viewModel.debtPressure),
                icon: "exclamationmark.triangle.fill"
            )
            
            Divider()
                .frame(height: 20)
            
            // Guard status indicator
            GuardStatusIndicator(status: viewModel.guardStatus)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .help(statusTooltip)
    }
    
    private func readinessColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }
    
    private func debtColor(_ pressure: Double) -> Color {
        if pressure <= 0.2 { return .green }
        if pressure <= 0.5 { return .yellow }
        return .red
    }
    
    private var statusTooltip: String {
        """
        RAG System Status:
        • Readiness: \(Int(viewModel.readinessScore * 100))% (index freshness, enrichment, confidence)
        • Debt Pressure: \(Int(viewModel.debtPressure * 100))% (duplicates, dead code, quality)
        • Guard: \(viewModel.guardStatus.rawValue.capitalized)
        """
    }
}

struct MetricIndicator: View {
    let label: String
    let value: Double
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 12))
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("\(Int(value * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

struct GuardStatusIndicator: View {
    let status: GuardStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text("Guard")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(status.rawValue.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .clear: return .green
        case .warn: return .yellow
        case .block: return .red
        }
    }
}

// MARK: - View Model

class RAGStatusGaugeViewModel: ObservableObject {
    @Published var readinessScore: Double = 0.0
    @Published var debtPressure: Double = 0.0
    @Published var guardStatus: GuardStatus = .clear
    
    private let eventBus: EventBusProtocol
    private var subscriptions: [AnyCancellable] = []
    
    // Metric accumulators
    private var indexFreshness: Double = 1.0
    private var enrichmentCoverage: Double = 0.0
    private var retrievalConfidence: Double = 0.0
    
    private var duplicateRiskCount: Int = 0
    private var deadCodeRiskCount: Int = 0
    private var qualityTrend: Double = 1.0
    
    init(eventBus: EventBusProtocol) {
        self.eventBus = eventBus
        subscribeToEvents()
    }
    
    private func subscribeToEvents() {
        // Subscribe to retrieval events
        subscriptions.append(
            eventBus.subscribe(to: RetrievalEvidencePreparedEvent.self) { [weak self] event in
                self?.updateRetrievalConfidence(event.retrievalConfidence)
            }
        )
        
        // Subscribe to prevention events
        subscriptions.append(
            eventBus.subscribe(to: PreWritePreventionCheckCompletedEvent.self) { [weak self] event in
                self?.updateGuardStatus(from: event)
            }
        )
        
        subscriptions.append(
            eventBus.subscribe(to: DuplicateRiskDetectedEvent.self) { [weak self] _ in
                self?.incrementDuplicateRisk()
            }
        )
        
        subscriptions.append(
            eventBus.subscribe(to: DeadCodeRiskDetectedEvent.self) { [weak self] _ in
                self?.incrementDeadCodeRisk()
            }
        )
        
        // Subscribe to index events
        subscriptions.append(
            eventBus.subscribe(to: IndexingCompletedEvent.self) { [weak self] event in
                self?.updateIndexFreshness(filesIndexed: 100)
            }
        )
    }
    
    private func updateRetrievalConfidence(_ confidence: Double) {
        retrievalConfidence = confidence
        recalculateReadiness()
    }
    
    private func updateIndexFreshness(filesIndexed: Int) {
        // Simplified: assume freshness based on file count
        indexFreshness = min(1.0, Double(filesIndexed) / 100.0)
        recalculateReadiness()
    }
    
    private func updateGuardStatus(from event: PreWritePreventionCheckCompletedEvent) {
        switch event.outcome {
        case "pass":
            guardStatus = .clear
        case "warn":
            guardStatus = .warn
        case "block":
            guardStatus = .block
        default:
            guardStatus = .clear
        }
    }
    
    private func incrementDuplicateRisk() {
        duplicateRiskCount += 1
        recalculateDebtPressure()
    }
    
    private func incrementDeadCodeRisk() {
        deadCodeRiskCount += 1
        recalculateDebtPressure()
    }
    
    private func recalculateReadiness() {
        // Readiness = weighted average of index freshness, enrichment coverage, and retrieval confidence
        readinessScore = (indexFreshness * 0.4 + enrichmentCoverage * 0.3 + retrievalConfidence * 0.3)
    }
    
    private func recalculateDebtPressure() {
        // Debt pressure = normalized risk counts + quality trend
        let duplicatePressure = min(1.0, Double(duplicateRiskCount) / 10.0)
        let deadCodePressure = min(1.0, Double(deadCodeRiskCount) / 10.0)
        let qualityPressure = 1.0 - qualityTrend
        
        debtPressure = (duplicatePressure * 0.4 + deadCodePressure * 0.4 + qualityPressure * 0.2)
    }
}

// MARK: - Models

enum GuardStatus: String, Sendable {
    case clear
    case warn
    case block
}

// MARK: - Preview
// Preview disabled - requires EventBus instance
