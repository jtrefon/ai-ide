import Foundation

actor AIToolExecutorConcurrencyTracker {
    private(set) var current: Int = 0
    private(set) var maxConcurrent: Int = 0

    func enter() {
        current += 1
        if current > maxConcurrent {
            maxConcurrent = current
        }
    }

    func exit() {
        current = max(0, current - 1)
    }
}
