import Foundation

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = max(0, value)
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            value += 1
        }
    }
}
