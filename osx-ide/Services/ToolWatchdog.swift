import Foundation

actor ToolWatchdog {
    private struct WatchEntry: Sendable {
        let toolCallId: String
        let deadline: ContinuousClock.Instant
        let continuation: UnsafeContinuation<Void, Error>
    }

    private var entries: [String: WatchEntry] = [:]
    private var timerTask: Task<Void, Never>?

    func watch(toolCallId: String, timeout: TimeInterval) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
            entries[toolCallId] = WatchEntry(
                toolCallId: toolCallId,
                deadline: deadline,
                continuation: continuation
            )
            if timerTask == nil { startTimer() }
        }
    }

    func cancel(_ toolCallId: String) {
        entries[toolCallId]?.continuation.resume()
        entries[toolCallId] = nil
        if entries.isEmpty { stopTimer() }
    }

    func extend(_ toolCallId: String, by seconds: TimeInterval) {
        guard let entry = entries[toolCallId] else { return }
        let newDeadline = entry.deadline + .seconds(seconds)
        entries[toolCallId] = WatchEntry(toolCallId: entry.toolCallId, deadline: newDeadline, continuation: entry.continuation)
    }

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                let now = ContinuousClock.now
                let expired = entries.filter { $0.value.deadline <= now }
                for (id, entry) in expired {
                    entry.continuation.resume(throwing: ToolExecutionError.executionFailed("Timed out"))
                    entries[id] = nil
                }
                if entries.isEmpty {
                    stopTimer()
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}
