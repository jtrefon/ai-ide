import Foundation

actor CompletionTelemetryService {
    private(set) var shownCount = 0
    private(set) var acceptedCount = 0
    private(set) var dismissedCount = 0
    private(set) var cancelledCount = 0
    private var recentLatencies: [Double] = []

    func recordShown(_ presentation: InlineSuggestionPresentation) {
        shownCount += 1
        recordLatency(presentation.latencyMs)
    }

    func recordAccepted() {
        acceptedCount += 1
    }

    func recordDismissed() {
        dismissedCount += 1
    }

    func recordCancelled() {
        cancelledCount += 1
    }

    func recentSlowCompletions(thresholdMs: Double = 400) -> Int {
        recentLatencies.suffix(6).filter { $0 >= thresholdMs }.count
    }

    func shouldReduceWorkload() -> Bool {
        recentSlowCompletions() >= 2
    }

    private func recordLatency(_ latency: Double) {
        recentLatencies.append(latency)
        if recentLatencies.count > 20 {
            recentLatencies.removeFirst(recentLatencies.count - 20)
        }
    }
}

